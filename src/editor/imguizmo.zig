const std = @import("std");
const vk = @import("vulkan");

const C = @cImport({
    @cInclude("imguizmo/ImGuizmo.h");
});

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const sdl = @import("../rendering/sdl.zig");

const Renderer = @import("../rendering/renderer.zig");
const AssetDB = @import("../rendering/assetdb.zig");

const Rtti = @import("../util/rtti.zig");
const zal = @import("zalgebra");

pub extern fn SetDrawlist(drawlist: ?*imgui.DrawList) void;
pub extern fn BeginFrame() void;
pub extern fn SetImGuiContext(ctx: *imgui.GuiContext) void;
pub extern fn IsOver() bool;
pub extern fn IsUsing() bool;
pub extern fn Enable(enable: bool) void;
// IMGUI_API void DecomposeMatrixToComponents(const float* matrix, float* translation, float* rotation, float* scale);
// IMGUI_API void RecomposeMatrixFromComponents(const float* translation, const float* rotation, const float* scale, float* matrix);
pub extern fn SetRect(x: f32, y: f32, width: f32, height: f32) void;
pub extern fn SetOrthographic(isOrthographic: bool) void;
// IMGUI_API void DrawCubes(const float* view, const float* projection, const float* matrices, int matrixCount);
// IMGUI_API void DrawGrid(const float* view, const float* projection, const float* matrix, const float gridSize);
pub extern fn Manipulate(view: *const zal.Mat4, projection: *const zal.Mat4, operation: Operation, mode: Mode, matrix: *zal.Mat4, deltaMatrix: ?*zal.Mat4, snap: ?*const f32, localBounds: ?*const f32, boundsSnap: ?*const f32) bool;
// IMGUI_API void ViewManipulate(float* view, float length, ImVec2 position, ImVec2 size, ImU32 backgroundColor);
pub extern fn SetID(id: c_int) void;
pub extern fn IsOverOp(op: Operation) bool;
// IMGUI_API void SetGizmoSizeClipSpace(float value);
// IMGUI_API void AllowAxisFlip(bool value);

pub fn FlagsMixin(comptime FlagsType: type, comptime Int: type) type {
    return struct {
        pub const IntType = Int;
        pub fn toInt(self: FlagsType) IntType {
            return @bitCast(IntType, self);
        }
        pub fn fromInt(flags: IntType) FlagsType {
            return @bitCast(FlagsType, flags);
        }
        pub fn merge(lhs: FlagsType, rhs: FlagsType) FlagsType {
            return fromInt(toInt(lhs) | toInt(rhs));
        }
        pub fn intersect(lhs: FlagsType, rhs: FlagsType) FlagsType {
            return fromInt(toInt(lhs) & toInt(rhs));
        }
        pub fn complement(self: FlagsType) FlagsType {
            return fromInt(~toInt(self));
        }
        pub fn subtract(lhs: FlagsType, rhs: FlagsType) FlagsType {
            return fromInt(toInt(lhs) & toInt(rhs.complement()));
        }
        pub fn contains(lhs: FlagsType, rhs: FlagsType) bool {
            return toInt(intersect(lhs, rhs)) == toInt(rhs);
        }
    };
}

pub const Operation = packed struct {
    translate_x: bool = false,
    translate_y: bool = false,
    translate_z: bool = false,
    rotate_x: bool = false,
    rotate_y: bool = false,
    rotate_z: bool = false,
    rotate_screen: bool = false,
    scale_x: bool = false,
    scale_y: bool = false,
    scale_z: bool = false,
    bounds: bool = false,
    scale_xu: bool = false,
    scale_yu: bool = false,
    scale_zu: bool = false,
    _reserved_bit_14: bool = false,
    _reserved_bit_15: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    _reserved_bit_18: bool = false,
    _reserved_bit_19: bool = false,
    _reserved_bit_20: bool = false,
    _reserved_bit_21: bool = false,
    _reserved_bit_22: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,

    pub const translate = Operation{ .translate_x = true, .translate_y = true, .translate_z = true };
    pub const rotate = Operation{ .rotate_x = true, .rotate_y = true, .rotate_z = true, .rotate_screen = true };
    pub const scale = Operation{ .scale_x = true, .scale_y = true, .scale_z = true };
    pub const scaleu = Operation{ .scale_xu = true, .scale_yu = true, .scale_zu = true };
    pub const universal = Operation{
        .translate_x = true,
        .translate_y = true,
        .translate_z = true,
        .rotate_x = true,
        .rotate_y = true,
        .rotate_z = true,
        .rotate_screen = true,
        .scale_xu = true,
        .scale_yu = true,
        .scale_zu = true,
    };

    pub usingnamespace FlagsMixin(Operation, u32);
};

pub const Mode = enum(u32) {
    Local,
    World,
};
