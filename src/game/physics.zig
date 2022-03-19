const std = @import("std");

const imgui = @import("../editor/imgui.zig");
const imgui2 = @import("../editor/imgui2.zig");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec2i = math.GenericVector(2, i64);
const Vec2u = math.GenericVector(2, u64);
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const SpriteRenderer = @import("../rendering/sprite_renderer.zig");
const Profiler = @import("../editor/profiler.zig");
const Viewport = @import("../editor/viewport.zig");

const StringFormatter = @import("../util/string_formatter.zig");

const EntityId = @import("../ecs/entity.zig").EntityId;
const World = @import("../ecs/world.zig");
const Query = @import("../ecs/query.zig").Query;
const Commands = @import("../ecs/commands.zig");

const basic_components = @import("basic_components.zig");
const Time = basic_components.Time;
const TransformComponent = basic_components.TransformComponent;
const SpeedComponent = basic_components.SpeedComponent;
const Player = @import("player.zig").Player;
const EnemySpawner = @import("enemies.zig").EnemySpawner;

const PhysicsQuery = Query(.{ TransformComponent, PhysicsComponent });
const EntityHandle = PhysicsQuery.EntityHandle;

pub const GridCenterComponent = struct {};

pub const PhysicsComponent = struct {
    layer: u32 = 1,
    radius: f32 = 50,
    restitution: f32 = 0,
    dynamic_friction: f32 = 0,
    static_friction: f32 = 0,
    inverse_mass: f32 = 1,
};

pub const PhysicsActor = struct {
    //
};

const EntityPair = struct {
    a: EntityId,
    b: EntityId,
};

const EntityHandlePair = struct {
    a: *EntityHandle,
    b: *EntityHandle,

    pub fn format(self: *const @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "({}, {})", .{ self.a.id, self.b.id });
    }

    pub const Context = struct {
        pub fn hash(self: @This(), s: EntityHandlePair) u64 {
            _ = self;
            return std.hash_map.getAutoHashFn(usize, @This())(self, s.a.id ^ s.b.id);
        }
        pub fn eql(self: @This(), a: EntityHandlePair, b: EntityHandlePair) bool {
            _ = self;
            return (a.a.id == b.a.id and a.b.id == b.b.id) or (a.a.id == b.b.id and a.b.id == b.a.id);
        }
    };
};

const Manifold = struct {
    const Self = @This();

    a: *EntityHandle,
    b: *EntityHandle,
    penetration: f32,
    normal: Vec2,

    restitution: f32,
    dynamic_friction: f32,
    static_friction: f32,

    pub fn circleVsCircle(a: *EntityHandle, b: *EntityHandle) ?Self {
        const n = b.transform.position.sub(a.transform.position).xy();
        const r = a.physics.radius + b.physics.radius;
        var radius_sq = r * r;

        const len_sq = n.lengthSq();
        if (len_sq > radius_sq)
            return null;

        const d = @sqrt(len_sq);

        if (d != 0) {
            return Self{
                .a = a,
                .b = b,
                .penetration = r - d,
                .normal = n.scale(1 / d),
                .restitution = std.math.min(a.physics.restitution, b.physics.restitution),
                .dynamic_friction = @sqrt(a.physics.dynamic_friction * b.physics.dynamic_friction),
                .static_friction = @sqrt(a.physics.static_friction * b.physics.static_friction),
            };
        } else {
            return Self{
                .a = a,
                .b = b,
                .penetration = a.physics.radius,
                .normal = Vec2.new(1, 0),
                .restitution = std.math.min(a.physics.restitution, b.physics.restitution),
                .dynamic_friction = @sqrt(a.physics.dynamic_friction * b.physics.dynamic_friction),
                .static_friction = @sqrt(a.physics.static_friction * b.physics.static_friction),
            };
        }
    }

    pub fn positionalCorrection(self: *Self) void {
        const k_slop = 0.05; // PenetrationAllowance
        const percent = 0.4; // Penetration percentage to correct

        const correction = self.normal.toVec3(0).scale(percent * std.math.max(self.penetration - k_slop, 0) / (self.a.physics.inverse_mass + self.b.physics.inverse_mass));
        self.a.transform.position = self.a.transform.position.sub(correction.scale(self.a.physics.inverse_mass));
        self.b.transform.position = self.b.transform.position.add(correction.scale(self.b.physics.inverse_mass));
    }
};

const CollisionInfo = struct {
    //
};

const GridCell = struct {
    entities: std.ArrayList(EntityHandle),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return @This(){
            .entities = std.ArrayList(EntityHandle).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.entities.deinit();
    }

    pub fn clear(self: *@This()) void {
        self.entities.clearRetainingCapacity();
    }

    pub fn insertEntity(self: *@This(), entity: *const EntityHandle) !void {
        try self.entities.append(entity.*);
    }
};

pub const PhysicsScene = struct {
    const Self = @This();

    world: *World,
    collisions: [2]std.AutoHashMap(EntityPair, CollisionInfo),
    potential_collisions: std.ArrayList(EntityHandlePair),
    manifolds: std.ArrayList(Manifold),
    index: usize = 0,

    grid: std.ArrayList(GridCell),
    grid_size_base: usize,
    grid_size_mask: usize,
    grid_size: usize,
    grid_cell_size: f32,

    center_cell: Vec2i = Vec2i.zero(),
    grid_offset: Vec2i = Vec2i.zero(),
    center_location: Vec2 = Vec2.zero(),

    pub fn init(allocator: std.mem.Allocator, world: *World) !Self {
        const grid_size_base = 5;
        const grid_size = 1 << grid_size_base;
        var grid = std.ArrayList(GridCell).init(allocator);
        try grid.resize(grid_size * grid_size);
        for (grid.items) |*cell| {
            cell.* = GridCell.init(allocator);
        }
        return Self{
            .world = world,
            .collisions = .{
                std.AutoHashMap(EntityPair, CollisionInfo).init(allocator),
                std.AutoHashMap(EntityPair, CollisionInfo).init(allocator),
            },
            .potential_collisions = std.ArrayList(EntityHandlePair).init(allocator),
            .manifolds = std.ArrayList(Manifold).init(allocator),
            .grid = grid,
            .grid_size_base = grid_size_base,
            .grid_size_mask = (1 << grid_size_base) - 1,
            .grid_size = grid_size,
            .grid_cell_size = 100,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.collisions[0..]) |*map| {
            map.deinit();
        }
        for (self.grid.items) |*cell| {
            cell.deinit();
        }
        self.grid.deinit();
        self.potential_collisions.deinit();
        self.manifolds.deinit();
    }

    pub fn clearGrid(self: *Self) void {
        for (self.grid.items) |*cell| {
            cell.clear();
        }
    }

    pub fn setCenterLocation(self: *Self, center_location: Vec2) void {
        self.center_location = center_location;
        self.center_cell = self.worldLocationToWorldCell(center_location);
        self.grid_offset = self.center_cell.sub(Vec2i.set(@intCast(i64, self.grid_size) >> 1));
    }

    pub fn insertEntity(self: *Self, entity: *const EntityHandle) !void {
        const world_location = entity.transform.position;
        const world_cell = self.worldLocationToWorldCell(world_location.xy());
        const relative_cell = self.worldCellToRelativeCell(world_cell); // used for bounds check
        // if (relative_cell.x() & self.grid_size_mask != relative_cell.x() or relative_cell.y() & self.grid_size_mask != relative_cell.y()) {
        if (!Vec2i.eql(relative_cell, relative_cell.bit_and(Vec2i.set(@intCast(i64, self.grid_size_mask))))) {
            // Out of bounds
            return;
        }
        var cell = self.getCell(world_cell);
        try cell.insertEntity(entity);
    }

    pub fn worldCellToRelativeCell(self: *Self, world_cell: Vec2i) Vec2i {
        return world_cell.sub(self.grid_offset);
    }

    pub fn relativeCellToWorldCell(self: *Self, relative_cell: Vec2i) Vec2i {
        return relative_cell.add(self.grid_offset);
    }

    pub fn worldLocationToWorldCell(self: *Self, world_location: Vec2) Vec2i {
        return world_location.divFloor(Vec2.set(self.grid_cell_size)).cast(i64);
    }

    pub fn getCell(self: *Self, world_cell: Vec2i) *GridCell {
        const clamped_cell = world_cell.bit_and(Vec2i.set(@intCast(i64, self.grid_size_mask))).cast(u64);
        return &self.grid.items[clamped_cell.x() + clamped_cell.y() * self.grid_size];
    }
};

pub fn physicsSystem(
    profiler: *Profiler,
    time: *const Time,
    sprite_renderer: *SpriteRenderer,
    commands: *Commands,
    spawner: *EnemySpawner,
    scene: *PhysicsScene,
    viewport: *Viewport,
    query: PhysicsQuery,
    grid_centers: Query(.{ GridCenterComponent, TransformComponent }),
) !void {
    const scope = profiler.beginScope("physicsSystem");
    defer scope.end();

    const draw_debug_entities = imgui2.variable(physicsSystem, bool, "(Physics) Draw entities", false, true, .{}).*;

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var grid_center = grid_centers.iter().next() orelse {
        std.log.warn("physicsSystem: No grid center found.", .{});
        return;
    };

    scene.clearGrid();
    scene.setCenterLocation(grid_center.transform.position.xy());

    // Collect entities into grid.
    {
        var iter = query.iter();
        while (iter.next()) |entity| {
            if (draw_debug_entities) {
                try drawDebugInfoForEntity(sprite_renderer, &entity);
            }

            try scene.insertEntity(&entity);
        }
    }

    if (imgui2.variable(physicsSystem, bool, "(Physics) Draw grid", false, true, .{}).*) {
        try drawDebugGrid(scene, viewport);
    }

    // Find possible collision pairs.
    scene.potential_collisions.clearRetainingCapacity();
    scene.manifolds.clearRetainingCapacity();

    _ = spawner;
    _ = commands;

    var y: i64 = 0;
    while (y < @intCast(i64, scene.grid_size) - 1) : (y += 1) {
        var x: i64 = 0;
        while (x < @intCast(i64, scene.grid_size) - 1) : (x += 1) {
            const relative_cell = Vec2i.new(x, y);
            const world_cell = scene.relativeCellToWorldCell(relative_cell);

            const cell_a = scene.getCell(world_cell);

            for (cell_a.entities.items) |*entity_a| {
                var y0 = y;
                var y1 = std.math.min(scene.grid_size - 1, y + 1);
                while (y0 <= y1) : (y0 += 1) {
                    const x_offset = y0 - y; // first 0, then 1
                    var x0 = std.math.max(0, x - x_offset);
                    var x1 = std.math.min(scene.grid_size - 1, x + 1);
                    while (x0 <= x1) : (x0 += 1) {
                        const cell_b = scene.getCell(scene.relativeCellToWorldCell(Vec2i.new(x0, y0)));
                        for (cell_b.entities.items) |*entity_b| {
                            if (entity_a.id == entity_b.id or (x0 == x and y0 == y and entity_a.id < entity_b.id))
                                continue;
                            try scene.potential_collisions.append(.{ .a = entity_a, .b = entity_b });
                        }
                    }
                }
            }
        }
    }

    imgui2.variable(physicsSystem, usize, "EntityHandlePairs", 0, true, .{}).* = scene.potential_collisions.items.len;

    const count = query.count();
    imgui2.variable(physicsSystem, usize, "Entities Sq", 0, true, .{}).* = count * count;

    if (imgui2.variable(physicsSystem, bool, "Draw potential collisions", false, true, .{}).*) {
        // Draw potential_collisions
        try drawDebugEntityHandlePairs(scene, viewport);
    }

    for (scene.potential_collisions.items) |pair| {
        if (Manifold.circleVsCircle(pair.a, pair.b)) |m| {
            try scene.manifolds.append(m);
        }
    }
    imgui2.variable(physicsSystem, usize, "Manifolds", 0, true, .{}).* = scene.manifolds.items.len;

    if (imgui2.variable(physicsSystem, bool, "Draw actual collisions", false, true, .{}).*) {
        // Draw potential_collisions
        try drawDebugManifolds(scene, viewport);
    }

    // Integrate forces

    // Solve collisions
    var iterations = imgui2.variable(physicsSystem, u64, "(Physics) Solve iterations", 1, true, .{}).*;
    while (iterations > 0) : (iterations -= 1) {}

    // Integrate velocities

    // Correct positions

    for (scene.manifolds.items) |*m| {
        m.positionalCorrection();
    }
    // Clear all forces
}

pub fn drawDebugEntityHandlePairs(
    scene: *PhysicsScene,
    viewport: *Viewport,
) !void {
    const open = imgui.Begin("Viewport");
    defer imgui.End();

    if (open) {
        const canvas_p0 = imgui.GetWindowContentRegionMin().toZal().add(imgui.GetWindowPos().toZal()); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetWindowContentRegionMax().toZal().sub(imgui.GetWindowContentRegionMin().toZal()); // Resize canvas to what's available
        if (canvas_sz.x() <= 1 or canvas_sz.y() <= 1) {
            return;
        }
        const canvas_p1 = Vec2.new(canvas_p0.x() + canvas_sz.x(), canvas_p0.y() + canvas_sz.y());

        var drawList = imgui.GetWindowDrawList() orelse return;
        drawList.PushClipRect(canvas_p0.toImgui2(), canvas_p1.toImgui2());
        defer drawList.PopClipRect();

        for (scene.potential_collisions.items) |*collision| {
            const p0 = viewport.world3ToViewport(collision.a.transform.position);
            const p1 = viewport.world3ToViewport(collision.b.transform.position);
            const color = imgui.ColorConvertFloat4ToU32(.{ .x = 1, .y = 0.15, .z = 1, .w = 1 });
            drawList.AddLine(p0.toImgui2(), p1.toImgui2(), color);
        }
    }
}

pub fn drawDebugManifolds(
    scene: *PhysicsScene,
    viewport: *Viewport,
) !void {
    const open = imgui.Begin("Viewport");
    defer imgui.End();

    if (open) {
        const canvas_p0 = imgui.GetWindowContentRegionMin().toZal().add(imgui.GetWindowPos().toZal()); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetWindowContentRegionMax().toZal().sub(imgui.GetWindowContentRegionMin().toZal()); // Resize canvas to what's available
        if (canvas_sz.x() <= 1 or canvas_sz.y() <= 1) {
            return;
        }
        const canvas_p1 = Vec2.new(canvas_p0.x() + canvas_sz.x(), canvas_p0.y() + canvas_sz.y());

        var drawList = imgui.GetWindowDrawList() orelse return;
        drawList.PushClipRect(canvas_p0.toImgui2(), canvas_p1.toImgui2());
        defer drawList.PopClipRect();

        for (scene.manifolds.items) |*manifold| {
            const p0 = viewport.world3ToViewport(manifold.a.transform.position);
            const p1 = viewport.world3ToViewport(manifold.b.transform.position);
            const color = imgui.ColorConvertFloat4ToU32(.{ .x = 0.15, .y = 1, .z = 1, .w = 1 });
            drawList.AddLine(p0.toImgui2(), p1.toImgui2(), color);
        }
    }
}

pub fn drawDebugGrid(
    scene: *PhysicsScene,
    viewport: *Viewport,
) !void {
    imgui2.variable(drawDebugGrid, Vec2, "center_cell", comptime Vec2.zero(), true, .{}).* = scene.center_cell.cast(f32);
    imgui2.variable(drawDebugGrid, Vec2, "grid_offset", comptime Vec2.zero(), true, .{}).* = scene.grid_offset.cast(f32);
    imgui2.variable(drawDebugGrid, Vec2, "center_location", comptime Vec2.zero(), true, .{}).* = scene.center_location;

    const open = imgui.Begin("Viewport");
    defer imgui.End();

    if (open) {
        var string_formatter = StringFormatter.init(std.heap.c_allocator);
        defer string_formatter.deinit();

        const canvas_p0 = imgui.GetWindowContentRegionMin().toZal().add(imgui.GetWindowPos().toZal()); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetWindowContentRegionMax().toZal().sub(imgui.GetWindowContentRegionMin().toZal()); // Resize canvas to what's available
        if (canvas_sz.x() <= 1 or canvas_sz.y() <= 1) {
            return;
        }
        const canvas_p1 = Vec2.new(canvas_p0.x() + canvas_sz.x(), canvas_p0.y() + canvas_sz.y());

        var drawList = imgui.GetWindowDrawList() orelse return;
        drawList.PushClipRect(canvas_p0.toImgui2(), canvas_p1.toImgui2());
        defer drawList.PopClipRect();

        var y: i64 = 0;
        while (y < @intCast(i64, scene.grid_size)) : (y += 1) {
            var x: i64 = 0;
            while (x < @intCast(i64, scene.grid_size)) : (x += 1) {
                const relative_cell = Vec2i.new(x, y);
                const world_cell = scene.relativeCellToWorldCell(relative_cell);
                const world_location = world_cell.cast(f32).scale(scene.grid_cell_size);

                const p0 = world_location;
                const p1 = p0.add(Vec2.set(scene.grid_cell_size));

                const p0_screen = viewport.world2ToViewport(p0);
                const p1_screen = viewport.world2ToViewport(p1);

                const is_current = Vec2i.eql(world_cell, scene.center_cell);
                const color = if (is_current) imgui.ColorConvertFloat4ToU32(.{ .x = 1, .y = 0.15, .z = 0.5, .w = 1 }) else imgui.ColorConvertFloat4ToU32(.{ .x = 0.15, .y = 1, .z = 0.5, .w = 1 });

                drawList.AddRect(p0_screen.toImgui2(), p1_screen.toImgui2(), color);

                const world_text = try string_formatter.format("{}, {}", .{ world_cell.x(), world_cell.y() });
                drawList.AddTextVec2(p0_screen.add(Vec2.new(5, -15)).toImgui2(), color, world_text.ptr);

                const relative_text = try string_formatter.format("{}, {}", .{ relative_cell.x(), relative_cell.y() });
                drawList.AddTextVec2(p0_screen.add(Vec2.new(5, -30)).toImgui2(), color, relative_text.ptr);

                const cell = scene.getCell(world_cell);

                const entities_text = try string_formatter.format("{}", .{cell.entities.items.len});
                drawList.AddTextVec2(p0_screen.add(Vec2.new(5, -45)).toImgui2(), color, entities_text.ptr);
            }
        }
    }
}

pub fn drawDebugInfoForEntity(
    sprite_renderer: *SpriteRenderer,
    entity: *const EntityHandle,
) !void {
    const open = imgui.Begin("Viewport");
    defer imgui.End();

    if (open) {
        const canvas_p0 = imgui.GetWindowContentRegionMin().toZal().add(imgui.GetWindowPos().toZal()); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetWindowContentRegionMax().toZal().sub(imgui.GetWindowContentRegionMin().toZal()); // Resize canvas to what's available
        if (canvas_sz.x() <= 1 or canvas_sz.y() <= 1) {
            return;
        }
        const canvas_p1 = Vec2.new(canvas_p0.x() + canvas_sz.x(), canvas_p0.y() + canvas_sz.y());

        var drawList = imgui.GetWindowDrawList() orelse return;
        drawList.PushClipRect(canvas_p0.toImgui2(), canvas_p1.toImgui2());
        defer drawList.PopClipRect();
        const position = entity.transform.position;
        const size = Vec2.set(entity.transform.size * entity.physics.radius);

        // Transform positions into screen space
        const view = sprite_renderer.matrices.view;
        const proj = sprite_renderer.matrices.proj;
        const screen = Mat4.orthographic(canvas_p0.x(), canvas_p1.x(), canvas_p0.y(), canvas_p1.y(), 1, -1).inv();

        const p0_world = Vec3.new(position.x(), position.y(), 0);
        const p1_world = Vec3.new(position.x() + size.x(), position.y(), 0);
        const p0_view = view.mulByVec3(p0_world, 1);
        const p1_view = view.mulByVec3(p1_world, 1);
        const p0_clip = proj.mulByVec3(p0_view, 1);
        const p1_clip = proj.mulByVec3(p1_view, 1);
        const p0_screen = screen.mulByVec3(p0_clip, 1);
        const p1_screen = screen.mulByVec3(p1_clip, 1);

        const p0 = Vec2.new(p0_screen.x(), p0_screen.y());
        const p1 = Vec2.new(p1_screen.x(), p1_screen.y());
        const radius = p0.sub(p1).length();

        const color = imgui.ColorConvertFloat4ToU32(.{ .x = 0.15, .y = 0.5, .z = 1, .w = 1 });

        // Draw outline
        drawList.AddCircle(
            p0.toImgui2(),
            radius,
            color,
        );
    }
}
