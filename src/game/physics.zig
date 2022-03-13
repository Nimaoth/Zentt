const std = @import("std");

const imgui = @import("../editor/imgui.zig");
const imgui2 = @import("../editor/imgui2.zig");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const SpriteRenderer = @import("../rendering/sprite_renderer.zig");
const Profiler = @import("../editor/profiler.zig");

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

pub const PhysicsComponent = struct {
    layer: u32 = 1,
    radius: f32 = 50,
};

pub const PhysicsActor = struct {
    //
};

const EntityPair = struct {
    a: EntityId,
    b: EntityId,
};

const CollisionInfo = struct {
    //
};

const GridCell = struct {
    entities: std.ArrayList(EntityId),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return @This(){
            .entities = std.ArrayList(EntityId).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.entities.deinit();
    }
};

pub const PhysicsScene = struct {
    const Self = @This();

    world: *World,
    collisions: [2]std.AutoHashMap(EntityPair, CollisionInfo),
    index: usize = 0,

    grid: std.ArrayList(GridCell),
    grid_size: usize,
    grid_cell_size: f32,

    pub fn init(allocator: std.mem.Allocator, world: *World) !Self {
        return Self{
            .world = world,
            .collisions = .{
                std.AutoHashMap(EntityPair, CollisionInfo).init(allocator),
                std.AutoHashMap(EntityPair, CollisionInfo).init(allocator),
            },
            .grid = std.ArrayList(GridCell).init(allocator),
            .grid_size = 10,
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
    }
};

const PhysicsQuery = Query(.{ TransformComponent, PhysicsComponent });

pub fn physicsSystem(
    profiler: *Profiler,
    time: *const Time,
    sprite_renderer: *SpriteRenderer,
    commands: *Commands,
    spawner: *EnemySpawner,
    scene: *PhysicsScene,
    query: PhysicsQuery,
) !void {
    const scope = profiler.beginScope("physicsSystem");
    defer scope.end();

    const draw_debug = imgui2.variable(physicsSystem, bool, "Debug physics", true, true, .{}).*;

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    _ = scene;

    var iter = query.iter();
    while (iter.next()) |entity| {
        var iter2 = query.iter();

        var got_destroyed = false;
        if (entity.physics.layer == 2) {
            // Enemy
            while (iter2.next()) |entity2| {
                const combined_radius = entity.physics.radius + entity2.physics.radius;
                const distance_sq = entity.transform.position.sub(entity2.transform.position).lengthSq();
                if (distance_sq < combined_radius * combined_radius) {
                    if (entity2.physics.layer == 4 and !got_destroyed) {
                        try commands.destroyEntity(entity.id);
                        spawner.current_count -= 1;
                        got_destroyed = true;
                    }
                }
            }
        }

        if (draw_debug) {
            try drawDebugInfoForEntity(sprite_renderer, &entity);
        }
    }
}

pub fn drawDebugInfoForEntity(
    sprite_renderer: *SpriteRenderer,
    entity: *const PhysicsQuery.EntityHandle,
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
        drawList.PushClipRect(canvas_p0.toImgui(), canvas_p1.toImgui());
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
            p0.toImgui(),
            radius,
            color,
        );
    }
}
