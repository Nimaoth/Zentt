const std = @import("std");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;

const Renderer = @import("../rendering/renderer.zig");
const SpriteRenderer = @import("../rendering/sprite_renderer.zig");
const AssetDB = @import("../rendering/assetdb.zig");

const Profiler = @import("../editor/profiler.zig");

const World = @import("../ecs/world.zig");
const Query = @import("../ecs/query.zig").Query;
const Commands = @import("../ecs/commands.zig");

const basic_components = @import("basic_components.zig");
const Time = basic_components.Time;
const TransformComponent = basic_components.TransformComponent;
const SpriteComponent = basic_components.SpriteComponent;
const AnimatedSpriteComponent = basic_components.AnimatedSpriteComponent;
const CameraComponent = basic_components.CameraComponent;

pub fn animatedSpriteRenderSystem(
    renderer: *Renderer,
    sprite_renderer: *SpriteRenderer,
    commands: *Commands,
    time: *const Time,
    cameras: Query(.{ TransformComponent, CameraComponent }),
    query: Query(.{ TransformComponent, AnimatedSpriteComponent }),
) !void {
    const scope = Profiler.beginScope("animatedSpriteRenderSystem");
    defer scope.end();

    const delta = @floatCast(f32, time.delta);

    if (cameras.iter().next()) |camera| {
        const height = std.math.max(camera.camera.size, 1);
        const aspect_ratio = @intToFloat(f32, renderer.current_scene_extent.width) / @intToFloat(f32, renderer.current_scene_extent.height);

        const matrices = SpriteRenderer.SceneMatricesUbo{
            // x needs to be flipped because the view matrix is the inverse of the camera transform
            // y needs to not be flipped because in vulkan y is flipped.
            .view = Mat4.fromTranslate(Vec3.fromSlice(&.{ -camera.transform.position.x(), -camera.transform.position.y(), 0 })),
            .proj = Mat4.orthographic(-height * aspect_ratio * 0.5, height * aspect_ratio * 0.5, height * 0.5, -height * 0.5, -500, 1000),
        };
        try sprite_renderer.updateCameraData(&matrices);
    } else {
        std.log.warn("spriteRenderSystem: No camera found", .{});
    }

    var iter = query.iter();
    entity_loop: while (iter.next()) |entity| {
        const position = entity.transform.position;
        const rotation = entity.transform.rotation;
        const size = entity.transform.size;

        if (delta > 0) {
            //
            entity.animated_sprite.time += delta;
            while (entity.animated_sprite.time >= entity.animated_sprite.anim.length) {
                entity.animated_sprite.time -= entity.animated_sprite.anim.length;
                if (entity.animated_sprite.destroy_at_end) {
                    _ = try commands.destroyEntity(entity.id);
                    continue :entity_loop;
                }
            }
        }

        const texture = entity.animated_sprite.getCurrentTexture();
        const texture_size: Vec2 = texture.getSize().scale(size);

        sprite_renderer.drawSprite(
            position,
            texture_size,
            rotation,
            texture,
            Vec2.new(1, 1),
            @intCast(u32, entity.id),
        );
    }
}

pub fn spriteRenderSystem(
    renderer: *Renderer,
    sprite_renderer: *SpriteRenderer,
    cameras: Query(.{ TransformComponent, CameraComponent }),
    query: Query(.{ TransformComponent, SpriteComponent }),
) !void {
    const scope = Profiler.beginScope("spriteRenderSystem");
    defer scope.end();

    if (cameras.iter().next()) |camera| {
        const height = std.math.max(camera.camera.size, 1);
        const aspect_ratio = @intToFloat(f32, renderer.current_scene_extent.width) / @intToFloat(f32, renderer.current_scene_extent.height);

        const matrices = SpriteRenderer.SceneMatricesUbo{
            // x needs to be flipped because the view matrix is the inverse of the camera transform
            // y needs to not be flipped because in vulkan y is flipped.
            .view = Mat4.fromTranslate(Vec3.fromSlice(&.{ -camera.transform.position.x(), -camera.transform.position.y(), 0 })),
            .proj = Mat4.orthographic(-height * aspect_ratio * 0.5, height * aspect_ratio * 0.5, height * 0.5, -height * 0.5, -500, 1000),
        };
        try sprite_renderer.updateCameraData(&matrices);
    } else {
        std.log.warn("spriteRenderSystem: No camera found", .{});
    }

    var iter = query.iter();
    while (iter.next()) |entity| {
        const position = entity.transform.position;
        const rotation = entity.transform.rotation;
        const size = entity.transform.size;

        const texture_size: Vec2 = entity.sprite.texture.getSize().scale(size);

        sprite_renderer.drawSprite(
            position,
            texture_size,
            rotation,
            entity.sprite.texture,
            entity.sprite.tiling,
            @intCast(u32, entity.id),
        );
    }
}
