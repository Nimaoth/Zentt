const std = @import("std");
const vk = @import("vulkan");
const c = @import("vulkan/c.zig");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const sdl = @import("sdl.zig");

const Vec2 = imgui.Vec2;
const Allocator = std.mem.Allocator;

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const resources = @import("resources");

const app_name = "vulkan-zig triangle example";
const Renderer = @import("renderer.zig");
const App = @import("app.zig");
const Details = @import("details_window.zig");

const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;
const Tag = @import("tag_component.zig").Tag;
const Commands = @import("commands.zig");
const Profiler = @import("profiler.zig");

pub const TransformComponent = struct {
    position: Vec2 = .{ .x = 0, .y = 0 },
    size: Vec2 = .{ .x = 50, .y = 50 },
};

pub const RenderComponent = struct {};

pub fn staticVariable(comptime scope: anytype, comptime T: type, comptime name: []const u8, comptime defaultValue: T, editable: bool) *T {
    _ = scope;
    _ = name;
    const Scope = struct {
        var staticVar: T = defaultValue;
    };
    if (editable) {
        _ = imgui.Begin("Static Variables");
        imgui2.any(&Scope.staticVar, name);
        imgui.End();
    }
    return &Scope.staticVar;
}

pub fn moveSystem(profiler: *Profiler, commands: *Commands, time: *const Time, query: Query(.{TransformComponent})) !void {
    const scope = profiler.beginScope("moveSystem");
    defer scope.end();

    var prng = std.rand.DefaultPrng.init(@floatToInt(u64, time.now));
    var rand = prng.random();

    // comptime var i = 0;
    // inline while (i < 10) : (i += 1) _ = rand.int(u64);

    var speed = staticVariable(moveSystem, f32, "speed", 0.1, true);
    var radius = staticVariable(moveSystem, f32, "radius", 100, true);
    var maxEntities = staticVariable(moveSystem, u64, "max_entities", 10, true);
    var addRenderComponent = staticVariable(moveSystem, bool, "add render component", true, true).*;

    var iter = query.iter();
    var i: u64 = 0;
    while (iter.next()) |entity| : (i += 1) {
        if (i >= maxEntities.*) {
            try commands.destroyEntity(entity.id);
            continue;
        }

        const velocity = (Vec2{ .x = rand.floatNorm(f32), .y = rand.floatNorm(f32) }).timess(speed.*);
        _ = entity.TransformComponent.position.add(velocity.timess(@floatCast(f32, time.delta)));

        const pos = entity.TransformComponent.position;
        if (pos.lenSq() > radius.* * radius.*) {
            try commands.destroyEntity(entity.id);
            if (addRenderComponent) {
                _ = (try commands.createEntity())
                    .addComponent(TransformComponent{ .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } })
                    .addComponent(RenderComponent{});
                _ = (try commands.createEntity())
                    .addComponent(TransformComponent{ .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } })
                    .addComponent(RenderComponent{});
            } else {
                _ = (try commands.createEntity())
                    .addComponent(TransformComponent{ .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } });
                _ = (try commands.createEntity())
                    .addComponent(TransformComponent{ .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } });
            }
        }
    }

    try profiler.record("moveSystemEntities", @intToFloat(f64, i));
}

pub fn renderSystem(profiler: *Profiler, query: Query(.{ TransformComponent, RenderComponent })) !void {
    const scope = profiler.beginScope("renderSystem");
    defer scope.end();

    imgui.PushStyleVarVec2(.WindowPadding, Vec2{});
    defer imgui.PopStyleVar();
    _ = imgui.Begin("Viewport");
    defer imgui.End();

    var cameraSize = staticVariable(renderSystem, f32, "cameraSize", 100, true);
    if (cameraSize.* < 0.1) {
        cameraSize.* = 0.1;
    }

    const canvas_p0 = imgui.GetCursorScreenPos(); // ImDrawList API uses screen coordinates!
    var canvas_sz = imgui.GetContentRegionAvail(); // Resize canvas to what's available
    if (canvas_sz.x < 50) canvas_sz.x = 50;
    if (canvas_sz.y < 50) canvas_sz.y = 50;
    const canvas_p1 = Vec2{ .x = canvas_p0.x + canvas_sz.x, .y = canvas_p0.y + canvas_sz.y };

    const aspectRatio = canvas_sz.x / canvas_sz.y;
    _ = aspectRatio;
    const scale = canvas_sz.y / cameraSize.*;

    var drawList = imgui.GetWindowDrawList() orelse return;
    drawList.PushClipRect(canvas_p0, canvas_p1);
    defer drawList.PopClipRect();

    var iter = query.iter();
    while (iter.next()) |entity| {
        const renderComponent = entity.RenderComponent;
        _ = renderComponent;

        const position = entity.TransformComponent.position.timess(scale).plus(canvas_p0).plus(canvas_sz.timess(0.5));
        const size = entity.TransformComponent.size.timess(scale);
        drawList.AddRect(position, position.plus(size), 0xff00ffff);
    }
}

const Time = struct {
    delta: f64 = 0,
    now: f64 = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // init SDL
    var app = try App.init(allocator);
    defer app.deinit();

    var world = try World.init(allocator);
    defer world.deinit();
    defer world.dumpGraph() catch {};
    try world.addSystem(renderSystem, "Render System");
    try world.addSystem(moveSystem, "Move System");

    _ = try world.addResource(Time{});
    var commands = try world.addResource(Commands.init(allocator));
    defer commands.deinit();

    var profiler = &app.profiler;
    try world.addResourcePtr(profiler);

    const e = try commands.createEntity();
    _ = try commands.addComponent(e, Tag{ .name = "e" });
    _ = try commands.addComponent(e, TransformComponent{});
    _ = try commands.addComponent(e, RenderComponent{});
    _ = try commands.applyCommands(world, std.math.maxInt(u64));

    var details = Details.init(allocator);
    var selectedEntity: EntityId = if (world.entities.valueIterator().next()) |it| it.id else 0;

    var lastFrameTime = std.time.nanoTimestamp();
    var frameTimeSmoothed: f64 = 0;

    while (app.isRunning) {
        try app.beginFrame();

        const currentFrameTime = std.time.nanoTimestamp();
        const frameTimeNs = currentFrameTime - lastFrameTime;
        const frameTime = (@intToFloat(f64, frameTimeNs) / std.time.ns_per_ms);
        frameTimeSmoothed = (0.9 * frameTimeSmoothed) + (0.1 * frameTime);
        lastFrameTime = currentFrameTime;
        var fps: f64 = blk: {
            if (frameTimeSmoothed == 0) {
                break :blk -1;
            } else {
                break :blk (1000.0 / frameTimeSmoothed);
            }
        };

        var timeResource = try world.getResource(Time);
        timeResource.delta = @intToFloat(f64, frameTimeNs) / std.time.ns_per_s;
        timeResource.now += timeResource.delta;

        var b = true;
        imgui2.showDemoWindow(&b);

        if (imgui.Begin("Stats")) {
            imgui.LabelText("Frame time: ", "%.2f", frameTimeSmoothed);
            imgui.LabelText("FPS: ", "%.1f", fps);
            imgui.LabelText("Entities: ", "%lld", world.entities.count());
        }
        imgui.End();

        try profiler.record("Frame", frameTime);

        try profiler.record("Entities", @intToFloat(f64, world.entities.count()));
        {
            const scope = profiler.beginScope("details and profiler");
            defer scope.end();

            if (imgui.Begin("Entities")) {
                if (imgui.Button("Create Entity")) {
                    const entt = try commands.createEntity();
                    _ = entt;
                }

                var tableFlags = imgui.TableFlags{
                    .Resizable = true,
                    .RowBg = true,
                    .Sortable = true,
                };
                tableFlags = tableFlags.with(imgui.TableFlags.Borders);
                if (imgui.BeginTable("Entities", 4, tableFlags, .{}, 0)) {
                    defer imgui.EndTable();

                    var i: u64 = 0;
                    var entityIter = world.entities.iterator();
                    while (entityIter.next()) |entry| : (i += 1) {
                        if (i > 100) break;
                        const entityId = entry.key_ptr.*;
                        imgui.PushIDInt64(entityId);
                        defer imgui.PopID();

                        imgui.TableNextRow(.{}, 0);
                        _ = imgui.TableSetColumnIndex(0);
                        imgui.Text("%d", entityId);

                        _ = imgui.TableSetColumnIndex(1);
                        if (try world.getComponent(entityId, Tag)) |tag| {
                            imgui.Text("%.*s", tag.name.len, tag.name.ptr);
                        }

                        _ = imgui.TableSetColumnIndex(2);
                        if (imgui.Button("Select")) {
                            // const entt = try commands.getEntity(entityId);
                            // _ = try commands.addComponent(entt, Tag{ .name = "lol" });
                            selectedEntity = entityId;
                        }

                        _ = imgui.TableSetColumnIndex(3);
                        if (imgui.Button("Destroy")) {
                            try commands.destroyEntity(entityId);
                        }
                    }
                }
            }
            imgui.End();

            try details.draw(world, selectedEntity, commands);
            try profiler.draw();
        }

        {
            const scope = profiler.beginScope("runFrameSystems");
            defer scope.end();
            try world.runFrameSystems();
        }

        {
            const scope = profiler.beginScope("applyCommands");
            defer scope.end();

            try profiler.record("Num commands (req)", @intToFloat(f64, commands.commands.items.len));

            var maxCommands = staticVariable(main, u64, "max_commands", 1000, true).*;
            const count = commands.applyCommands(world, maxCommands) catch |err| blk: {
                std.log.err("applyCommands failed: {}", .{err});
                break :blk 0;
            };
            try profiler.record("Num commands (run)", @intToFloat(f64, count));
        }

        try app.endFrame();
    }
}
