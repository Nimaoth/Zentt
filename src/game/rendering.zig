const std = @import("std");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;

const imgui = @import("../editor/imgui.zig");
const imgui2 = @import("../editor/imgui2.zig");

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

pub fn spriteRenderSystem(
    renderer: *Renderer,
    sprite_renderer: *SpriteRenderer,
    commands: *Commands,
    time: *const Time,
    cameras: Query(.{ TransformComponent, CameraComponent }),
    sprite_query: Query(.{ TransformComponent, SpriteComponent }),
    animated_sprite_query: Query(.{ TransformComponent, AnimatedSpriteComponent }),
) !void {
    const scope = Profiler.beginScope("animatedSpriteRenderSystem");
    defer scope.end();

    const delta = @floatCast(f32, time.delta);

    var camera_half_width: f32 = 1000000;
    var camera_half_height: f32 = 1000000;
    var cull_center = Vec2.zero();

    if (cameras.iter().next()) |camera| {
        const height = std.math.max(camera.camera.size, 1);
        const aspect_ratio = @intToFloat(f32, renderer.current_scene_extent.width) / @intToFloat(f32, renderer.current_scene_extent.height);

        const matrices = SpriteRenderer.SceneMatricesUbo{
            // x needs to be flipped because the view matrix is the inverse of the camera transform
            // y needs to not be flipped because in vulkan y is flipped.
            .view = Mat4.fromTranslate(Vec3.fromSlice(&.{ -camera.transform.position.x(), -camera.transform.position.y(), 0 })),
            .proj = Mat4.orthographic(-height * aspect_ratio * 0.5, height * aspect_ratio * 0.5, height * 0.5, -height * 0.5, -500, 1000),
        };

        // Use 0.6 for a bit of buffer around the edge.
        camera_half_width = height * aspect_ratio * 0.6;
        camera_half_height = height * 0.6;
        cull_center = Vec2.new(camera.transform.position.x(), camera.transform.position.y());

        try sprite_renderer.updateCameraData(&matrices);
    } else {
        std.log.warn("spriteRenderSystem: No camera found", .{});
    }

    const cull_rect_min = cull_center.sub(Vec2.new(camera_half_width, camera_half_height));
    const cull_rect_max = cull_center.add(Vec2.new(camera_half_width, camera_half_height));

    var rendered_entities: usize = 0;
    var culled_entities: usize = 0;
    var animated: usize = 0;
    var not_animated: usize = 0;

    // Animated Sprites
    {
        var iter = animated_sprite_query.iter();
        entity_loop: while (iter.next()) |entity| {
            animated += 1;

            const position = entity.transform.position;
            const rotation = entity.transform.rotation;
            const size = entity.transform.size;

            if (delta > 0) {
                //
                entity.animated_sprite.time += delta;
                while (entity.animated_sprite.time >= entity.animated_sprite.anim.length) {
                    entity.animated_sprite.time -= entity.animated_sprite.anim.length;
                    if (entity.animated_sprite.destroy_at_end) {
                        _ = try commands.destroyEntity(entity.ref.*);
                        continue :entity_loop;
                    }
                }
            }

            const texture = entity.animated_sprite.getCurrentTexture();
            const texture_size: Vec2 = texture.getSize().scale(size);

            const rect_min = position.xy().sub(texture_size.scale(0.5));
            const rect_max = rect_min.add(texture_size);

            if (rect_min.x() < cull_rect_max.x() and rect_max.x() > cull_rect_min.x() and rect_min.y() < cull_rect_max.y() and rect_max.y() > cull_rect_min.y()) {
                sprite_renderer.drawSprite(
                    position,
                    texture_size,
                    rotation,
                    texture,
                    Vec2.new(1, 1),
                    @intCast(u32, entity.ref.id),
                );
                rendered_entities += 1;
            } else {
                culled_entities += 1;
            }
        }
    }

    // Regular sprites
    {
        var iter = sprite_query.iter();
        while (iter.next()) |entity| {
            not_animated += 1;

            const position = entity.transform.position;
            const rotation = entity.transform.rotation;
            const size = entity.transform.size;

            const texture_size: Vec2 = entity.sprite.texture.getSize().scale(size);

            const rect_min = position.xy().sub(texture_size.scale(0.5));
            const rect_max = rect_min.add(texture_size);

            if (rect_min.x() < cull_rect_max.x() and rect_max.x() > cull_rect_min.x() and rect_min.y() < cull_rect_max.y() and rect_max.y() > cull_rect_min.y()) {
                sprite_renderer.drawSprite(
                    position,
                    texture_size,
                    rotation,
                    entity.sprite.texture,
                    entity.sprite.tiling,
                    @intCast(u32, entity.ref.id),
                );
                rendered_entities += 1;
            } else {
                culled_entities += 1;
            }
        }
    }

    const open = imgui.Begin("Stats");
    defer imgui.End();
    if (open) {
        var total = animated + not_animated;
        imgui2.any(&total, "Total sprites", .{});
        imgui2.any(&animated, "Animated sprites", .{});
        imgui2.any(&not_animated, "Normal sprites", .{});
        imgui2.any(&culled_entities, "Culled", .{});
        imgui2.any(&rendered_entities, "Rendered", .{});
    }
}
