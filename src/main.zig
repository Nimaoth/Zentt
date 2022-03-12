const std = @import("std");

const imgui = @import("editor/imgui.zig");
const imgui2 = @import("editor/imgui2.zig");
const imguizmo = @import("editor/imguizmo.zig");
const sdl = @import("rendering/sdl.zig");

const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;

const App = @import("app.zig");
const Renderer = @import("rendering/renderer.zig");
const SpriteRenderer = @import("rendering/sprite_renderer.zig");
const AssetDB = @import("rendering/assetdb.zig");

const Profiler = @import("editor/profiler.zig");
const Details = @import("editor/details_window.zig");
const ChunkDebugger = @import("editor/chunk_debugger.zig");
const Viewport = @import("editor/viewport.zig");

const EntityId = @import("ecs/entity.zig").EntityId;
const ComponentId = @import("ecs/entity.zig").ComponentId;
const World = @import("ecs/world.zig");
const EntityBuilder = @import("ecs/entity_builder.zig");
const Query = @import("ecs/query.zig").Query;
const Tag = @import("ecs/tag_component.zig").Tag;
const Commands = @import("ecs/commands.zig");

const app_name = "vulkan-zig triangle example";

const assets = @import("assets.zig");

const game = @import("game/game.zig");

pub fn moveSystemFollowPlayer(
    profiler: *Profiler,
    // commands: *Commands,
    time: *const game.Time,
    // assetdb: *AssetDB,
    players: Query(.{ game.Player, game.TransformComponent }),
    query: Query(.{ game.FollowPlayerMovementComponent, game.TransformComponent, game.SpeedComponent }),
) !void {
    const scope = profiler.beginScope("moveSystemFollowPlayer");
    defer scope.end();

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var player = players.iter().next() orelse {
        std.log.warn("moveSystemFollowPlayer: Player not found", .{});
        return;
    };

    var iter = query.iter();
    while (iter.next()) |entity| {
        const toPlayer = player.transform.position.sub(entity.transform.position).mul(Vec3.new(1, 1, 0));
        if (toPlayer.lengthSq() < 20 * 20) {
            const distance = toPlayer.norm().scale(-400);
            entity.transform.position = entity.transform.position.add(distance);
        } else {
            const vel = toPlayer.norm().scale(entity.speed.speed);
            entity.transform.position = entity.transform.position.add(vel.scale(delta));
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    var world = try World.init(allocator);
    defer world.deinit();
    defer world.dumpGraph() catch {};
    try world.addSystem(moveSystemFollowPlayer, "Move System Follow Player");
    try world.addSystem(game.Player.moveSystemPlayer, "Move System Player");
    try world.addSystem(game.bibleSystem, "Bible");

    try world.addRenderSystem(game.spriteRenderSystem, "Render System Vulkan");
    try world.addRenderSystem(game.animatedSpriteRenderSystem, "Render System Vulkan");

    _ = try world.addResource(game.Time{});
    var commands = try world.addResource(Commands.init(allocator));
    defer commands.deinit();

    var input = try world.addResource(game.Input{});

    var assetdb = try world.addResource(try AssetDB.init(allocator, &app.renderer.gc));
    defer assetdb.deinit();

    try assets.loadAssets(assetdb);

    var profiler = &app.profiler;
    try world.addResourcePtr(profiler);

    try world.addResourcePtr(app.renderer);
    try world.addResourcePtr(app.sprite_renderer);

    _ = (try commands.createEntity())
        .addComponent(game.Player{})
        .addComponent(game.TransformComponent{ .position = Vec3.new(100, 0, 0), .size = 1 })
        .addComponent(game.SpeedComponent{ .speed = 150 })
        .addComponent(game.CameraComponent{ .size = 450 })
        .addComponent(game.AnimatedSpriteComponent{ .anim = assetdb.getSpriteAnimation("Antonio") orelse unreachable });

    // Background.
    _ = (try commands.createEntity())
        .addComponent(game.TransformComponent{ .position = Vec3.new(0, 0, 100), .size = 1000 })
        .addComponent(game.SpriteComponent{ .texture = try assetdb.getTextureByPath("Forest_119.png", .{}), .tiling = Vec2.new(1000, 1000) });

    try game.createBible(commands, assetdb);
    try game.createBible(commands, assetdb);
    try game.createBible(commands, assetdb);
    try game.createBible(commands, assetdb);

    // {
    // const animation_count = assetdb.sprite_animations.count();
    // const x_count = std.math.sqrt(animation_count);
    //     var prng = std.rand.DefaultPrng.init(123);
    //     var rand = prng.random();

    //     var iter = assetdb.sprite_animations.valueIterator();
    //     var pos = Vec3.zero();
    //     var i: usize = 0;
    //     while (iter.next()) |asset| : (i += 1) {
    //         const anim: *AssetDB.SpriteAnimationAsset = asset.*;
    //         _ = (try commands.createEntity())
    //             .addComponent(game.TransformComponent{ .position = pos, .size = 1 })
    //             .addComponent(game.AnimatedSpriteComponent{ .anim = anim })
    //             .addComponent(game.SpeedComponent{ .speed = std.math.max(1, rand.floatNorm(f32) * 25 + 50) })
    //             .addComponent(game.FollowPlayerMovementComponent{});

    //         if (i >= x_count) {
    //             i = 0;
    //             pos = pos.mul(Vec3.new(0, 1, 1)).add(Vec3.new(0, 50, 0));
    //         } else {
    //             pos = pos.add(Vec3.new(50, 0, 0));
    //         }
    //     }
    // }
    // {
    //     var pos = Vec3.new(-500, -600, 0);
    //     for (assetdb.textures.items) |asset| {
    //         if (asset.data == .image) {
    //             _ = (try commands.createEntity())
    //                 .addComponent(game.TransformComponent{ .position = pos.add(Vec3.new(@intToFloat(f32, asset.data.image.image.extent.width) * 0.5, 0, 0)), .size = 0.5 })
    //                 .addComponent(game.SpriteComponent{ .texture = asset });
    //             pos = pos.add(Vec3.new(@intToFloat(f32, asset.data.image.image.extent.width) + 10, 0, 0));
    //             // } else if (std.mem.startsWith(u8, asset.path, "Forest_")) {
    //             //     _ = (try commands.createEntity())
    //             //         .addComponent(TransformComponent{ .position = pos.plus(.{ .x = asset.getSize().x() * 0.5 }), .size = 1 })
    //             //         .addComponent(SpriteComponent{ .texture = asset });
    //             //     pos.x += asset.getSize().x() + 10;
    //         }
    //     }
    // }

    _ = try commands.applyCommands(world);

    var details = Details.init(allocator);
    defer details.deinit();
    try details.registerDefaultComponent(game.Player{});
    try details.registerDefaultComponent(game.TransformComponent{});
    try details.registerDefaultComponent(game.FollowPlayerMovementComponent{});
    try details.registerDefaultComponent(game.CameraComponent{ .size = 400 });

    var viewport = Viewport.init(world, app);

    var selectedEntity: EntityId = if (world.entities.valueIterator().next()) |it| it.id else 0;

    var chunkDebugger = ChunkDebugger.init(allocator);
    defer chunkDebugger.deinit();

    var lastFrameTime = std.time.nanoTimestamp();
    var frameTimeSmoothed: f64 = 0;

    defer app.waitIdle();
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

        var timeResource = try world.getResource(game.Time);
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

        {
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

        try details.draw(world, selectedEntity, commands);
        try profiler.draw();
        try chunkDebugger.draw(world);

        {
            const scope = profiler.beginScope("runFrameSystems");
            defer scope.end();

            world.runFrameSystems() catch |err| {
                std.log.err("Failed to run frame systems: {}", .{err});
            };
        }

        {
            const scope = profiler.beginScope("runRenderSystems");
            defer scope.end();

            try app.beginRender();
            world.runRenderSystems() catch |err| {
                std.log.err("Failed to run render systems: {}", .{err});
            };
            try app.endRender();
        }

        var viewport_click_location: ?Vec2 = try viewport.draw(selectedEntity);

        {
            const scope = profiler.beginScope("applyCommands");
            defer scope.end();

            try profiler.record("Num commands (req)", @intToFloat(f64, commands.commands.items.len));

            commands.applyCommands(world) catch |err| {
                std.log.err("applyCommands failed: {}", .{err});
            };
        }

        try app.endFrame();

        if (viewport_click_location) |loc| {
            //
            const id = try app.renderer.getIdAt(@floatToInt(usize, loc.x()), @floatToInt(usize, loc.y()));
            if (world.entities.get(id)) |_| {
                selectedEntity = id;
            } else if (id == 0) {
                selectedEntity = id;
            }
        }
    }
}
