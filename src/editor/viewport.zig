const std = @import("std");

const C = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
});

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const imguizmo = @import("imguizmo.zig");
const zal = @import("zalgebra");

const Renderer = @import("../rendering/renderer.zig");
const AssetDB = @import("../rendering/assetdb.zig");
const World = @import("../ecs/world.zig");
const App = @import("../app.zig");

const Rtti = @import("../util/rtti.zig");
const EntityId = @import("../ecs/entity.zig").EntityId;

const Vec2 = imgui.Vec2;

const TransformComponent = @import("root").TransformComponent;
const SpriteComponent = @import("root").SpriteComponent;
const AnimatedSpriteComponent = @import("root").AnimatedSpriteComponent;

const Self = @This();

world: *World,
app: *App,

pub fn init(
    world: *World,
    app: *App,
) @This() {
    return @This(){
        .world = world,
        .app = app,
    };
}

pub fn draw(self: *Self, selected_entity: EntityId) !?Vec2 {
    const open = imgui.Begin("Viewport");
    defer imgui.End();

    var viewport_click_location: ?Vec2 = null;

    if (open) {
        const canvas_p0 = imgui.GetWindowContentRegionMin().plus(imgui.GetWindowPos()); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetWindowContentRegionMax().minus(imgui.GetWindowContentRegionMin()); // Resize canvas to what's available
        if (canvas_sz.x < 50) canvas_sz.x = 50;
        if (canvas_sz.y < 50) canvas_sz.y = 50;
        const canvas_p1 = Vec2{ .x = canvas_p0.x + canvas_sz.x, .y = canvas_p0.y + canvas_sz.y };

        const aspectRatio = canvas_sz.x / canvas_sz.y;
        _ = aspectRatio;

        var drawList = imgui.GetWindowDrawList() orelse return null;
        drawList.PushClipRect(canvas_p0, canvas_p1);
        defer drawList.PopClipRect();

        var using_gizmo = false;

        if (self.world.entities.get(selected_entity)) |entity| {
            if (try self.world.getComponent(entity.id, TransformComponent)) |transform| {
                var texture_size = zal.Vec2.new(1, 1);

                if (try self.world.getComponent(entity.id, SpriteComponent)) |sprite| {
                    texture_size = sprite.texture.getSize();
                } else if (try self.world.getComponent(entity.id, AnimatedSpriteComponent)) |animated_sprite| {
                    texture_size = animated_sprite.getCurrentTexture().getSize();
                }

                const position = transform.position;
                const size = (Vec2{ .x = texture_size.x(), .y = texture_size.y() }).timess(0.5 * transform.size);

                // Transform positions into screen space
                const view = self.app.sprite_renderer.matrices.view.transpose();
                const proj = self.app.sprite_renderer.matrices.proj;
                const screen = zal.Mat4.orthographic(canvas_p0.x, canvas_p1.x, canvas_p0.y, canvas_p1.y, 1, -1).inv();

                const p0_world = zal.Vec3.new(position.x - size.x, position.y - size.y, 0); // Invert y
                const p1_world = zal.Vec3.new(position.x + size.x, position.y + size.y, 0); // Invert y
                const p0_view = view.mulByVec3(p0_world, 1);
                const p1_view = view.mulByVec3(p1_world, 1);
                const p0_clip = proj.mulByVec3(p0_view, 1);
                const p1_clip = proj.mulByVec3(p1_view, 1);
                const p0_screen = screen.mulByVec3(p0_clip, 1);
                const p1_screen = screen.mulByVec3(p1_clip, 1);

                const p0 = Vec2{ .x = p0_screen.x(), .y = p0_screen.y() };
                const p1 = Vec2{ .x = p1_screen.x(), .y = p1_screen.y() };

                const color = imgui.ColorConvertFloat4ToU32(imgui2.variable(draw, imgui.Vec4, "Selection Color", .{ .x = 1, .y = 0.5, .z = 0.15, .w = 1 }, true, .{ .color = true }).*);
                const thickness = imgui2.variable(draw, u64, "Selection Thickness", 3, true, .{ .min = 2 }).*;

                // Draw outline
                var i: u64 = 0;
                while (i < thickness) : (i += 1) {
                    const f = @intToFloat(f32, i);
                    drawList.AddRect(
                        p0.minus(.{ .x = f, .y = f }),
                        p1.plus(.{ .x = f, .y = f }),
                        if (i == 0) 0xff000000 else color,
                    );
                }

                // Transform guizmo
                imguizmo.SetDrawlist(null);
                imguizmo.SetOrthographic(true);
                imguizmo.SetRect(canvas_p0.x, canvas_p0.y, canvas_sz.x, canvas_sz.y);

                var mode = imgui2.variable(draw, imguizmo.Mode, "Guizmo Mode", .World, true, .{});
                if (imgui.IsKeyPressed(imgui.Key.@"1")) {
                    mode.* = .Local;
                } else if (imgui.IsKeyPressed(imgui.Key.@"2")) {
                    mode.* = .World;
                }

                var entity_transform = zal.Mat4.recompose(
                    zal.Vec3.new(position.x, position.y, 0),
                    zal.Vec3.new(0, 0, if (mode.* == .World) 0 else transform.rotation),
                    zal.Vec3.new(transform.size, transform.size, 1),
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
                    transform.position.x = comps.t.x();
                    transform.position.y = comps.t.y();
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
            const mouse_pos = imgui.GetMousePos().minus(canvas_p0);
            if (mouse_pos.x >= border and mouse_pos.y >= border and mouse_pos.x + border < canvas_sz.x and mouse_pos.y + border < canvas_sz.y) {
                viewport_click_location = mouse_pos;
            }
        }
    }

    return viewport_click_location;
}
