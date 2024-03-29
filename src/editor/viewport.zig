const std = @import("std");

const C = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
});

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const imguizmo = @import("imguizmo.zig");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Renderer = @import("../rendering/renderer.zig");
const AssetDB = @import("../rendering/assetdb.zig");
const World = @import("../ecs/world.zig");
const App = @import("../app.zig");

const Rtti = @import("../util/rtti.zig");
const Entity = @import("../ecs/entity.zig");
const EntityRef = Entity.Ref;
const EntityId = Entity.EntityId;

const game = @import("../game/game.zig");
const TransformComponent = game.TransformComponent;
const SpriteComponent = game.SpriteComponent;
const AnimatedSpriteComponent = game.AnimatedSpriteComponent;

const Self = @This();

world: *World,
app: *App,
content_size: imgui.Vec2 = .{},
screen_matrix: Mat4 = Mat4.identity(),

pub fn init(
    world: *World,
    app: *App,
) @This() {
    return @This(){
        .world = world,
        .app = app,
    };
}

pub fn drawScene(self: *Self) !void {
    imgui.PushStyleVarVec2(.WindowPadding, .{});
    defer imgui.PopStyleVar();

    const open = imgui.Begin("Viewport");
    defer imgui.End();

    if (open) {
        const size = imgui.GetContentRegionAvail();
        self.content_size = size;
        imgui.ImageExt(
            @ptrCast(**anyopaque, &self.app.renderer.getSceneImage().descriptor).*,
            size,
            .{ .x = 0, .y = 0 },
            .{ .x = size.x / @intToFloat(f32, Renderer.scene_render_extent.width), .y = size.y / @intToFloat(f32, Renderer.scene_render_extent.height) }, // the size is the size of the scene frame buffer which doesn't get resized.
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            .{ .x = 0, .y = 0, .z = 0, .w = 0 },
        );
    }
}

pub fn prepare(self: *Self) void {
    const open = imgui.Begin("Viewport");
    defer imgui.End();

    if (open) {
        const canvas_p0 = imgui.GetWindowContentRegionMin().toZal().add(imgui.GetWindowPos().toZal()); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetWindowContentRegionMax().toZal().sub(imgui.GetWindowContentRegionMin().toZal()); // Resize canvas to what's available
        if (canvas_sz.x() <= 1 or canvas_sz.y() <= 1) {
            return;
        }
        const canvas_p1 = Vec2.new(canvas_p0.x() + canvas_sz.x(), canvas_p0.y() + canvas_sz.y());
        self.screen_matrix = Mat4.orthographic(canvas_p0.x(), canvas_p1.x(), canvas_p0.y(), canvas_p1.y(), 1, -1).inv();
    }
}

pub fn draw(self: *Self, selected_entity: EntityRef) !?Vec2 {
    const open = imgui.Begin("Viewport");
    defer imgui.End();

    var viewport_click_location: ?Vec2 = null;

    if (open) {
        const canvas_p0 = imgui.GetWindowContentRegionMin().toZal().add(imgui.GetWindowPos().toZal()); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetWindowContentRegionMax().toZal().sub(imgui.GetWindowContentRegionMin().toZal()); // Resize canvas to what's available
        if (canvas_sz.x() <= 1 or canvas_sz.y() <= 1) {
            return null;
        }
        const canvas_p1 = Vec2.new(canvas_p0.x() + canvas_sz.x(), canvas_p0.y() + canvas_sz.y());

        const aspectRatio = canvas_sz.x() / canvas_sz.y();
        _ = aspectRatio;

        var drawList = imgui.GetWindowDrawList() orelse return null;
        drawList.PushClipRect(canvas_p0.toImgui2(), canvas_p1.toImgui2());
        defer drawList.PopClipRect();

        var using_gizmo = false;

        if (selected_entity.isValid()) {
            if (try self.world.getComponent(selected_entity, TransformComponent)) |transform| {
                var texture_size = Vec2.new(1, 1);

                if (try self.world.getComponent(selected_entity, SpriteComponent)) |sprite| {
                    texture_size = sprite.texture.getSize();
                } else if (try self.world.getComponent(selected_entity, AnimatedSpriteComponent)) |animated_sprite| {
                    texture_size = animated_sprite.getCurrentTexture().getSize();
                }

                const position = transform.position;
                const size = Vec2.new(texture_size.x(), texture_size.y()).scale(0.5 * transform.size);

                // Transform positions into screen space
                const view = self.app.sprite_renderer.matrices.view;
                const proj = self.app.sprite_renderer.matrices.proj;

                const p0_screen = self.world2ToViewport(position.xy().sub(size));
                const p1_screen = self.world2ToViewport(position.xy().add(size));

                const p0 = Vec2.new(p0_screen.x(), p0_screen.y());
                const p1 = Vec2.new(p1_screen.x(), p1_screen.y());

                // const color = imgui.ColorConvertFloat4ToU32(imgui2.variable(draw, imgui.Vec4, "Selection Color", .{ .x = 1, .y = 0.5, .z = 0.15, .w = 1 }, true, .{ .color = true }).*);
                // const thickness = imgui2.variable(draw, u64, "Selection Thickness", 3, true, .{ .min = 2 }).*;
                const color = imgui.ColorConvertFloat4ToU32(.{ .x = 1, .y = 0.5, .z = 0.15, .w = 1 });
                const thickness = 3;

                // Draw outline
                var i: u64 = 0;
                while (i < thickness) : (i += 1) {
                    const f = @intToFloat(f32, i);
                    drawList.AddRect(
                        p0.sub(Vec2.from(.{ .x = f, .y = f })).toImgui2(),
                        p1.add(Vec2.from(.{ .x = f, .y = f })).toImgui2(),
                        if (i == 0) 0xff000000 else color,
                    );
                }

                // Transform guizmo
                imguizmo.SetDrawlist(null);
                imguizmo.SetOrthographic(true);
                imguizmo.SetRect(canvas_p0.x(), canvas_p0.y(), canvas_sz.x(), canvas_sz.y());

                var mode = imgui2.variable(draw, imguizmo.Mode, "Guizmo Mode", .World, false, .{});
                if (imgui.IsKeyPressed(imgui.Key.@"1")) {
                    mode.* = .Local;
                } else if (imgui.IsKeyPressed(imgui.Key.@"2")) {
                    mode.* = .World;
                }

                var entity_transform = Mat4.recompose(
                    Vec3.new(position.x(), position.y(), 0),
                    Vec3.new(0, 0, if (mode.* == .World) 0 else transform.rotation),
                    Vec3.new(transform.size, transform.size, 1),
                );

                // We need to invert the y axis of the projection matrix because vulkan uses inverse y but imguizmo does not.
                const guizmo_proj = proj.invertOrthographicY();

                if (imguizmo.Manipulate(
                    &view,
                    &guizmo_proj,
                    .{ .translate_x = true, .translate_y = true, .scale_x = true, .rotate_z = true },
                    mode.*,
                    &entity_transform,
                    null,
                    null,
                    null,
                    null,
                )) {
                    using_gizmo = true;
                    const comps = entity_transform.decompose();
                    transform.position = Vec3.new(comps.t.x(), comps.t.y(), transform.position.z());
                    transform.size = comps.s.x();
                    if (mode.* == .World) {
                        transform.rotation += comps.r.extractEulerAngles().z();
                    } else {
                        transform.rotation = comps.r.extractEulerAngles().z();
                    }
                }

                if (imguizmo.IsOverOp(imguizmo.Operation.translate) or imguizmo.IsUsing()) {
                    using_gizmo = true;
                }
            }
        }

        if (!using_gizmo and imgui.IsMouseClicked(.Left)) {
            const border = 5;
            const mouse_pos = imgui.GetMousePos().toZal().sub(canvas_p0);
            if (mouse_pos.x() >= border and mouse_pos.y() >= border and mouse_pos.x() + border < canvas_sz.x() and mouse_pos.y() + border < canvas_sz.y()) {
                viewport_click_location = mouse_pos;
            }
        }
    }

    return viewport_click_location;
}

pub fn world2ToViewport(self: *Self, position: Vec2) Vec2 {
    return self.world3ToViewport(Vec3.new(position.x(), position.y(), 0));
}

pub fn world3ToViewport(self: *Self, position: Vec3) Vec2 {
    const view = self.app.sprite_renderer.matrices.view;
    const proj = self.app.sprite_renderer.matrices.proj;

    const p0_view = view.mulByVec3(position, 1);
    const p0_clip = proj.mulByVec3(p0_view, 1);
    const p0_screen = self.screen_matrix.mulByVec3(p0_clip, 1);
    return p0_screen.xy();
}
