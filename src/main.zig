const std = @import("std");
const vk = @import("vulkan");
const c = @import("vulkan/c.zig");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const sdl = @import("sdl.zig");

const zal = @import("zalgebra");

const Vec2 = imgui.Vec2;
const Allocator = std.mem.Allocator;

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const resources = @import("resources");

const app_name = "vulkan-zig triangle example";
const Renderer = @import("renderer.zig");
const App = @import("app.zig");
const Details = @import("details_window.zig");
const ChunkDebugger = @import("editor/chunk_debugger.zig");

const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;
const Tag = @import("tag_component.zig").Tag;
const Commands = @import("commands.zig");
const Profiler = @import("profiler.zig");

const AssetDB = @import("assetdb.zig");

pub const TransformComponent = struct {
    position: Vec2 = .{ .x = 0, .y = 0 },
    vel: Vec2 = .{ .x = 0, .y = 0 },
    size: Vec2 = .{ .x = 50, .y = 50 },
};

pub const RenderComponent = struct {
    // texture: *AssetDB.TextureAsset,
};

pub fn moveSystemPlayer(
    profiler: *Profiler,
    time: *const Time,
    input: *const Input,
    query: Query(.{ Player, TransformComponent }),
) !void {
    const scope = profiler.beginScope("moveSystemPlayer");
    defer scope.end();

    _ = zal.toRadians(5.0);

    var maxSpeed = std.math.clamp(imgui2.variable(moveSystemPlayer, f32, "Player Max Speed", 150, true, .{}).*, 0, 100000);
    var acceleration = imgui2.variable(moveSystemPlayer, f32, "Player Acc", 1300, true, .{}).*;

    var iter = query.iter();
    while (iter.next()) |entity| {
        var dir = Vec2{};
        if (input.left) dir.x -= 1;
        if (input.right) dir.x += 1;
        if (input.up) dir.y -= 1;
        if (input.down) dir.y += 1;

        if (dir.lenSq() == 0) {
            dir = entity.TransformComponent.vel.timess(-1);
        }
        _ = dir.normalize();
        _ = entity.TransformComponent.vel.add(dir.timess(acceleration * @floatCast(f32, time.delta)));

        const len = entity.TransformComponent.vel.len();
        _ = entity.TransformComponent.vel.normalize();
        _ = entity.TransformComponent.vel.muls(std.math.clamp(len, 0, maxSpeed));

        _ = entity.TransformComponent.position.add(entity.TransformComponent.vel.timess(@floatCast(f32, time.delta)));
    }
}

pub fn moveSystemQuad(
    profiler: *Profiler,
    commands: *Commands,
    time: *const Time,
    players: Query(.{ Player, TransformComponent }),
    query: Query(.{ Quad, TransformComponent, RenderComponent }),
) !void {
    const scope = profiler.beginScope("moveSystemQuad");
    defer scope.end();

    var prng = std.rand.DefaultPrng.init(@floatToInt(u64, time.now * 10000));
    var rand = prng.random();

    var player = players.iter().next() orelse return error.NoPlayerFound;

    // comptime var i = 0;
    // inline while (i < 10) : (i += 1) _ = rand.int(u64);

    var speed = imgui2.variable(moveSystemQuad, f32, "speed", 0.1, true, .{});
    var radius = imgui2.variable(moveSystemQuad, f32, "radius", 100, true, .{});
    var maxEntities = imgui2.variable(moveSystemQuad, u64, "max_entities", 10, true, .{});
    var addRenderComponent = imgui2.variable(moveSystemQuad, bool, "add render component", true, true, .{}).*;
    var maxEntitiesSpawnedPerFrame = imgui2.variable(moveSystemQuad, u64, "Max spawnrate", 100, true, .{}).*;
    var antiGravity = imgui2.variable(moveSystemQuad, f32, "Anti Gravity", 5000, true, .{}).*;

    var entitiesSpawned: u64 = 0;

    const sizeSq = player.TransformComponent.size.x * player.TransformComponent.size.x;

    var iter = query.iter();
    var i: u64 = 0;
    while (iter.next()) |entity| : (i += 1) {
        if (i >= maxEntities.*) {
            try commands.destroyEntity(entity.id);
            continue;
        }

        // var velocity = (Vec2{ .x = rand.floatNorm(f32), .y = rand.floatNorm(f32) }).timess(speed.*);
        var velocity = entity.TransformComponent.vel.timess(speed.*);
        const toPlayer = entity.TransformComponent.position.plus(player.TransformComponent.position.timess(-1));
        const distSq = toPlayer.lenSq();
        if (distSq < sizeSq) {
            _ = velocity.add(toPlayer.normalized().timess(antiGravity / std.math.max(distSq, 0.1)));
        }

        _ = entity.TransformComponent.position.add(velocity.timess(@floatCast(f32, time.delta)));

        const pos = entity.TransformComponent.position;
        if (pos.lenSq() > radius.* * radius.*) {
            try commands.destroyEntity(entity.id);
            if (entitiesSpawned < maxEntitiesSpawnedPerFrame) {
                entitiesSpawned += 1;
                if (addRenderComponent) {
                    _ = (try commands.createEntity())
                        .addComponent(Quad{})
                        .addComponent(TransformComponent{ .vel = .{ .x = rand.float(f32) - 0.5, .y = rand.float(f32) - 0.5 }, .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } })
                    // .addComponent(RenderComponent{ .texture = entity.RenderComponent.texture });
                        .addComponent(RenderComponent{});
                    _ = (try commands.createEntity())
                        .addComponent(Quad{})
                        .addComponent(TransformComponent{ .vel = .{ .x = rand.float(f32) - 0.5, .y = rand.float(f32) - 0.5 }, .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } })
                    // .addComponent(RenderComponent{ .texture = entity.RenderComponent.texture });
                        .addComponent(RenderComponent{});
                } else {
                    _ = (try commands.createEntity())
                        .addComponent(Quad{})
                        .addComponent(TransformComponent{ .vel = .{ .x = rand.float(f32) - 0.5, .y = rand.float(f32) - 0.5 }, .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } });
                    _ = (try commands.createEntity())
                        .addComponent(Quad{})
                        .addComponent(TransformComponent{ .vel = .{ .x = rand.float(f32) - 0.5, .y = rand.float(f32) - 0.5 }, .size = .{ .x = rand.float(f32) * 15 + 5, .y = rand.float(f32) * 15 + 5 } });
                }
            }
        }
    }

    try profiler.record("moveSystemEntities", @intToFloat(f64, i));
}

pub fn renderSystemImgui(profiler: *Profiler, query: Query(.{ TransformComponent, RenderComponent })) !void {
    const scope = profiler.beginScope("renderSystemImgui");
    defer scope.end();

    imgui.PushStyleVarVec2(.WindowPadding, Vec2{});
    defer imgui.PopStyleVar();
    _ = imgui.Begin("renderSystemImgui");
    defer imgui.End();

    var cameraSize = imgui2.variable(renderSystemImgui, f32, "cameraSize", 500, true, .{});
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
        drawList.AddRect(position.plus(size.timess(-0.5)), position.plus(size.timess(0.5)), 0xff00ffff);
    }
}

pub fn renderSystemVulkan(profiler: *Profiler, renderer: *Renderer, query: Query(.{ TransformComponent, RenderComponent })) !void {
    const scope = profiler.beginScope("renderSystemVulkan");
    defer scope.end();

    var iter = query.iter();
    while (iter.next()) |entity| {
        const position = entity.TransformComponent.position;
        const size = entity.TransformComponent.size;
        _ = position;
        _ = size;
        _ = renderer;

        // if (entity.RenderComponent.texture) |tex| {
        // renderer.bindTexture(entity.RenderComponent.texture.descriptor);
        // }
        renderer.drawTriangle(zal.Vec4.new(position.x, position.y, size.x, size.y), .null_handle);
    }
}

const Player = struct {};
const Quad = struct {};

const Time = struct {
    delta: f64 = 0,
    now: f64 = 0,
};

const Input = struct {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
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
    try world.addSystem(moveSystemQuad, "Move System Quad");
    try world.addSystem(moveSystemPlayer, "Move System Player");

    // try world.addRenderSystem(renderSystemImgui, "Render System Imgui");
    try world.addRenderSystem(renderSystemVulkan, "Render System Vulkan");

    _ = try world.addResource(Time{});
    var commands = try world.addResource(Commands.init(allocator));
    defer commands.deinit();

    var input = try world.addResource(Input{});

    var assetdb = try world.addResource(try AssetDB.init(allocator, &app.renderer.gc));
    defer assetdb.deinit();

    var profiler = &app.profiler;
    try world.addResourcePtr(profiler);

    try world.addResourcePtr(app.renderer);

    const e = try commands.createEntity();
    _ = try commands.addComponent(e, Quad{});
    _ = try commands.addComponent(e, TransformComponent{ .position = .{ .x = -50 }, .vel = .{ .x = -1 } });
    _ = try commands.addComponent(e, RenderComponent{});
    // _ = try commands.addComponent(e, RenderComponent{ .texture = try assetdb.getTextureByPath("assets/img.jpg") });

    const player = (try commands.createEntity())
        .addComponent(Player{})
        .addComponent(TransformComponent{ .position = .{ .x = 100 }, .size = .{ .x = 50, .y = 50 } })
        .addComponent(RenderComponent{});
    // .addComponent(RenderComponent{ .texture = try assetdb.getTextureByPath("assets/img.jpg") });
    _ = try commands.applyCommands(world, std.math.maxInt(u64));
    _ = player;

    var details = Details.init(allocator);
    var selectedEntity: EntityId = if (world.entities.valueIterator().next()) |it| it.id else 0;

    var chunkDebugger = ChunkDebugger.init(allocator);
    defer chunkDebugger.deinit();

    var lastFrameTime = std.time.nanoTimestamp();
    var frameTimeSmoothed: f64 = 0;

    while (app.isRunning) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            _ = imgui2.ImGui_ImplSDL2_ProcessEvent(event);
            switch (event.@"type") {
                sdl.SDL_QUIT => {
                    app.isRunning = false;
                },
                sdl.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        sdl.SDLK_u => input.left = true,
                        sdl.SDLK_a => input.right = true,
                        sdl.SDLK_v => input.up = true,
                        sdl.SDLK_i => input.down = true,
                        else => {},
                    }
                },
                sdl.SDL_KEYUP => {
                    switch (event.key.keysym.sym) {
                        sdl.SDLK_u => input.left = false,
                        sdl.SDLK_a => input.right = false,
                        sdl.SDLK_v => input.up = false,
                        sdl.SDLK_i => input.down = false,
                        else => {},
                    }
                },
                else => {},
            }
        }

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
            const scope = profiler.beginScope("Entity list");
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
        }

        {
            const scope = profiler.beginScope("Details");
            defer scope.end();
            try details.draw(world, selectedEntity, commands);
        }
        {
            const scope = profiler.beginScope("Profiler");
            defer scope.end();
            try profiler.draw();
        }
        {
            const scope = profiler.beginScope("Chunk Debugger");
            defer scope.end();
            try chunkDebugger.draw(world);
        }

        {
            const scope = profiler.beginScope("runFrameSystems");
            defer scope.end();
            try world.runFrameSystems();
        }

        {
            const scope = profiler.beginScope("runRenderSystems");
            defer scope.end();

            try app.beginRender();
            try world.runRenderSystems();
            try app.endRender();
        }

        {
            const scope = profiler.beginScope("applyCommands");
            defer scope.end();

            try profiler.record("Num commands (req)", @intToFloat(f64, commands.commands.items.len));

            var maxCommands = imgui2.variable(main, u64, "max_commands", 1000, true, .{}).*;
            const count = commands.applyCommands(world, maxCommands) catch |err| blk: {
                std.log.err("applyCommands failed: {}", .{err});
                break :blk 0;
            };
            try profiler.record("Num commands (run)", @intToFloat(f64, count));
        }

        try app.endFrame();

        if (timeResource.now > 0.02) {
            // return;
        }
    }
}
