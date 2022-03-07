const std = @import("std");

const imgui = @import("editor/imgui.zig");
const imgui2 = @import("editor/imgui2.zig");
const sdl = @import("rendering/sdl.zig");

const zal = @import("zalgebra");

const Vec2 = imgui.Vec2;
const Allocator = std.mem.Allocator;

const App = @import("app.zig");
const Renderer = @import("rendering/renderer.zig");
const SpriteRenderer = @import("rendering/sprite_renderer.zig");
const AssetDB = @import("rendering/assetdb.zig");

const Profiler = @import("editor/profiler.zig");
const Details = @import("editor/details_window.zig");
const ChunkDebugger = @import("editor/chunk_debugger.zig");

const EntityId = @import("ecs/entity.zig").EntityId;
const ComponentId = @import("ecs/entity.zig").ComponentId;
const World = @import("ecs/world.zig");
const EntityBuilder = @import("ecs/entity_builder.zig");
const Query = @import("ecs/query.zig").Query;
const Tag = @import("ecs/tag_component.zig").Tag;
const Commands = @import("ecs/commands.zig");

const app_name = "vulkan-zig triangle example";

const assets = @import("assets.zig");

pub const TransformComponent = struct {
    position: Vec2 = .{ .x = 0, .y = 0 },
    size: f32 = 1,
};

pub const SpriteComponent = struct {
    texture: *AssetDB.TextureAsset,
};

pub const AnimatedSpriteComponent = struct {
    anim: *AssetDB.SpriteAnimationAsset,
    time: f32 = 0,

    pub fn getCurrentTextureIndex(self: *const @This()) usize {
        return @floatToInt(usize, (self.time / self.anim.length) * @intToFloat(f32, self.anim.sprites.len));
    }

    pub fn getCurrentTexture(self: *const @This()) *AssetDB.TextureAsset {
        return self.anim.sprites[self.getCurrentTextureIndex()];
    }
};

pub const CameraComponent = struct {
    size: f32,
};

pub const SpeedComponent = struct {
    speed: f32,
};

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

pub fn moveSystemPlayer(
    profiler: *Profiler,
    time: *const Time,
    input: *const Input,
    query: Query(.{ Player, TransformComponent, SpeedComponent }),
) !void {
    const scope = profiler.beginScope("moveSystemPlayer");
    defer scope.end();

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var iter = query.iter();
    while (iter.next()) |entity| {
        var dir = Vec2{};
        if (input.left) dir.x -= 1;
        if (input.right) dir.x += 1;
        if (input.up) dir.y += 1;
        if (input.down) dir.y -= 1;

        const vel = dir.normalized().timess(entity.speed.speed);
        _ = entity.transform.position.add(vel.timess(delta));
    }
}

pub fn moveSystemQuad(
    profiler: *Profiler,
    // commands: *Commands,
    time: *const Time,
    // assetdb: *AssetDB,
    players: Query(.{ Player, TransformComponent }),
    query: Query(.{ Quad, TransformComponent, SpriteComponent, SpeedComponent }),
) !void {
    const scope = profiler.beginScope("moveSystemQuad");
    defer scope.end();

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var player = players.iter().next() orelse {
        std.log.warn("moveSystemQuad: Player not found", .{});
        return;
    };

    var speed = imgui2.variable(moveSystemQuad, f32, "speed", 1, true, .{}).*;

    var iter = query.iter();
    while (iter.next()) |entity| {
        const toPlayer = player.transform.position.plus(entity.transform.position.timess(-1));
        const vel = toPlayer.normalized().timess(speed * entity.speed.speed);

        _ = entity.transform.position.add(vel.timess(delta));
    }
}

pub fn animatedSpriteRenderSystem(
    profiler: *Profiler,
    renderer: *Renderer,
    sprite_renderer: *SpriteRenderer,
    time: *const Time,
    cameras: Query(.{ TransformComponent, CameraComponent }),
    query: Query(.{ TransformComponent, AnimatedSpriteComponent }),
) !void {
    const scope = profiler.beginScope("spriteRenderSystem");
    defer scope.end();

    const delta = @floatCast(f32, time.delta);

    if (cameras.iter().next()) |camera| {
        const height = std.math.max(camera.camera.size, 1);
        const aspect_ratio = @intToFloat(f32, renderer.current_scene_extent.width) / @intToFloat(f32, renderer.current_scene_extent.height);

        const matrices = SpriteRenderer.SceneMatricesUbo{
            // x needs to be flipped because the view matrix is the inverse of the camera transform
            // y needs to not be flipped because in vulkan y is flipped.
            .view = zal.Mat4.fromTranslate(zal.Vec3.fromSlice(&.{ -camera.transform.position.x, camera.transform.position.y, 0 })).transpose(),
            .proj = zal.Mat4.orthographic(-height * aspect_ratio * 0.5, height * aspect_ratio * 0.5, -height * 0.5, height * 0.5, 1, -1),
        };
        try sprite_renderer.updateCameraData(&matrices);
    } else {
        std.log.warn("spriteRenderSystem: No camera found", .{});
    }

    var iter = query.iter();
    while (iter.next()) |entity| {
        const position = entity.transform.position;
        const size = entity.transform.size;

        if (delta > 0) {
            //
            entity.animated_sprite.time += delta;
            while (entity.animated_sprite.time >= entity.animated_sprite.anim.length) {
                entity.animated_sprite.time -= entity.animated_sprite.anim.length;
            }
        }

        const texture = entity.animated_sprite.getCurrentTexture();
        const texture_size: zal.Vec2 = texture.getSize().scale(size);

        sprite_renderer.drawSprite(zal.Vec4.new(position.x, position.y, texture_size.x(), texture_size.y()), texture, @intCast(u32, entity.id));
    }

    // const descriptor_set_count = sprite_renderer.frame_data[sprite_renderer.frame_index].image_descriptor_sets.count();

    // try profiler.record("Descriptor sets per frame", @intToFloat(f64, descriptor_set_count));
}

pub fn spriteRenderSystem(
    profiler: *Profiler,
    renderer: *Renderer,
    sprite_renderer: *SpriteRenderer,
    cameras: Query(.{ TransformComponent, CameraComponent }),
    query: Query(.{ TransformComponent, SpriteComponent }),
) !void {
    const scope = profiler.beginScope("spriteRenderSystem");
    defer scope.end();

    if (cameras.iter().next()) |camera| {
        const height = std.math.max(camera.camera.size, 1);
        const aspect_ratio = @intToFloat(f32, renderer.current_scene_extent.width) / @intToFloat(f32, renderer.current_scene_extent.height);

        const matrices = SpriteRenderer.SceneMatricesUbo{
            // x needs to be flipped because the view matrix is the inverse of the camera transform
            // y needs to not be flipped because in vulkan y is flipped.
            .view = zal.Mat4.fromTranslate(zal.Vec3.fromSlice(&.{ -camera.transform.position.x, camera.transform.position.y, 0 })).transpose(),
            .proj = zal.Mat4.orthographic(-height * aspect_ratio * 0.5, height * aspect_ratio * 0.5, -height * 0.5, height * 0.5, 1, -1),
        };
        try sprite_renderer.updateCameraData(&matrices);
    } else {
        std.log.warn("spriteRenderSystem: No camera found", .{});
    }

    var iter = query.iter();
    while (iter.next()) |entity| {
        const position = entity.transform.position;
        const size = entity.transform.size;

        const texture_size: zal.Vec2 = entity.sprite.texture.getSize().scale(size);

        sprite_renderer.drawSprite(zal.Vec4.new(position.x, position.y, texture_size.x(), texture_size.y()), entity.sprite.texture, @intCast(u32, entity.id));
    }

    const descriptor_set_count = sprite_renderer.frame_data[sprite_renderer.frame_index].image_descriptor_sets.count();

    try profiler.record("Descriptor sets per frame", @intToFloat(f64, descriptor_set_count));
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
    try world.addSystem(moveSystemQuad, "Move System Quad");
    try world.addSystem(moveSystemPlayer, "Move System Player");

    try world.addRenderSystem(spriteRenderSystem, "Render System Vulkan");
    try world.addRenderSystem(animatedSpriteRenderSystem, "Render System Vulkan");

    _ = try world.addResource(Time{});
    var commands = try world.addResource(Commands.init(allocator));
    defer commands.deinit();

    var input = try world.addResource(Input{});

    var assetdb = try world.addResource(try AssetDB.init(allocator, &app.renderer.gc));
    defer assetdb.deinit();

    try assets.loadAssets(assetdb);

    var profiler = &app.profiler;
    try world.addResourcePtr(profiler);

    try world.addResourcePtr(app.renderer);
    try world.addResourcePtr(app.sprite_renderer);

    _ = (try commands.createEntity())
        .addComponent(Player{})
        .addComponent(TransformComponent{ .position = .{ .x = 100 }, .size = 1 })
        .addComponent(SpeedComponent{ .speed = 150 })
        .addComponent(CameraComponent{ .size = 400 })
        .addComponent(AnimatedSpriteComponent{ .anim = assetdb.getSpriteAnimation("Antonio") orelse unreachable });

    const animation_count = assetdb.sprite_animations.count();
    const x_count = std.math.sqrt(animation_count);
    {
        var iter = assetdb.sprite_animations.valueIterator();
        var pos = Vec2{};
        var i: usize = 0;
        while (iter.next()) |asset| : (i += 1) {
            const anim: *AssetDB.SpriteAnimationAsset = asset.*;
            _ = (try commands.createEntity())
                .addComponent(Quad{})
                .addComponent(TransformComponent{ .position = pos, .size = 1 })
                .addComponent(AnimatedSpriteComponent{ .anim = anim })
                .addComponent(SpeedComponent{ .speed = 75 });

            if (i >= x_count) {
                i = 0;
                pos.x = 0;
                pos.y += 50;
            } else {
                pos.x += 50;
            }
        }
    }

    _ = try commands.applyCommands(world, std.math.maxInt(u64));

    var details = Details.init(allocator);
    defer details.deinit();
    try details.registerDefaultComponent(Quad{});
    try details.registerDefaultComponent(Player{});
    try details.registerDefaultComponent(TransformComponent{});
    // try details.registerDefaultComponent(SpriteComponent{ .texture = try assetdb.getTextureByPath("whiteDot.png", .{}) });
    try details.registerDefaultComponent(CameraComponent{ .size = 400 });

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

        var viewport_click_location: ?Vec2 = null;
        {
            const open = imgui.Begin("Viewport");
            defer imgui.End();

            if (open) {
                const canvas_p0 = imgui.GetWindowContentRegionMin().plus(imgui.GetWindowPos()); // ImDrawList API uses screen coordinates!
                var canvas_sz = imgui.GetWindowContentRegionMax().minus(imgui.GetWindowContentRegionMin()); // Resize canvas to what's available
                if (canvas_sz.x < 50) canvas_sz.x = 50;
                if (canvas_sz.y < 50) canvas_sz.y = 50;
                const canvas_p1 = Vec2{ .x = canvas_p0.x + canvas_sz.x, .y = canvas_p0.y + canvas_sz.y };

                const aspectRatio = canvas_sz.x / canvas_sz.y;
                _ = aspectRatio;

                var drawList = imgui.GetWindowDrawList() orelse return;
                drawList.PushClipRect(canvas_p0, canvas_p1);
                defer drawList.PopClipRect();

                if (world.entities.get(selectedEntity)) |entity| {
                    if (try world.getComponent(entity.id, TransformComponent)) |transform| {
                        var texture_size = zal.Vec2.new(1, 1);

                        if (try world.getComponent(entity.id, SpriteComponent)) |sprite| {
                            texture_size = sprite.texture.getSize();
                        } else if (try world.getComponent(entity.id, AnimatedSpriteComponent)) |animated_sprite| {
                            texture_size = animated_sprite.getCurrentTexture().getSize();
                        }

                        const position = transform.position;
                        const size = (Vec2{ .x = texture_size.x(), .y = texture_size.y() }).timess(0.5 * transform.size);

                        // Transform positions into screen space
                        const view = app.sprite_renderer.matrices.view.transpose();
                        const proj = app.sprite_renderer.matrices.proj;
                        const screen = zal.Mat4.orthographic(canvas_p0.x, canvas_p1.x, canvas_p0.y, canvas_p1.y, 1, -1).inv(); // Flip y

                        const p0_world = zal.Vec3.new(position.x - size.x, -position.y - size.y, 0); // Invert y
                        const p1_world = zal.Vec3.new(position.x + size.x, -position.y + size.y, 0); // Invert y
                        const p0_view = view.mulByVec3(p0_world, 1);
                        const p1_view = view.mulByVec3(p1_world, 1);
                        const p0_clip = proj.mulByVec3(p0_view, 1);
                        const p1_clip = proj.mulByVec3(p1_view, 1);
                        const p0_screen = screen.mulByVec3(p0_clip, 1);
                        const p1_screen = screen.mulByVec3(p1_clip, 1);

                        const p0 = Vec2{ .x = p0_screen.x(), .y = p0_screen.y() };
                        const p1 = Vec2{ .x = p1_screen.x(), .y = p1_screen.y() };

                        const color = imgui.ColorConvertFloat4ToU32(imgui2.variable(main, imgui.Vec4, "Selection Color", .{ .x = 1, .y = 0.5, .z = 0.15, .w = 1 }, true, .{ .color = true }).*);
                        const thickness = imgui2.variable(main, u64, "Selection Thickness", 3, true, .{ .min = 2 }).*;

                        var i: u64 = 0;
                        while (i < thickness) : (i += 1) {
                            const f = @intToFloat(f32, i);
                            drawList.AddRect(
                                p0.minus(.{ .x = f, .y = f }),
                                p1.plus(.{ .x = f, .y = f }),
                                if (i == 0) 0xff000000 else color,
                            );
                        }
                    }
                }

                if (imgui.IsMouseClicked(.Left)) {
                    const mouse_pos = imgui.GetMousePos().minus(canvas_p0);
                    if (mouse_pos.x >= 0 and mouse_pos.y >= 0 and mouse_pos.x < canvas_sz.x and mouse_pos.y < canvas_sz.y) {
                        viewport_click_location = mouse_pos;
                    }
                }
            }
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

        if (viewport_click_location) |loc| {
            //
            const id = try app.renderer.getIdAt(@floatToInt(usize, loc.x), @floatToInt(usize, loc.y));
            if (world.entities.get(id)) |_| {
                selectedEntity = id;
            } else if (id == 0) {
                selectedEntity = id;
            }
        }
    }
}
