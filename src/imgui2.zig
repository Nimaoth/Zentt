const std = @import("std");
const vk = @import("vulkan");

const C = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
});

const imgui = @import("imgui.zig");
const sdl = @import("sdl.zig");

const Rtti = @import("rtti.zig");

pub const ImGui_ImplVulkan_InitInfo = extern struct {
    Instance: vk.Instance,
    PhysicalDevice: vk.PhysicalDevice,
    Device: vk.Device,
    QueueFamily: u32,
    Queue: vk.Queue,
    PipelineCache: [*c]vk.PipelineCache,
    DescriptorPool: vk.DescriptorPool,
    Subpass: u32 = 0,
    MinImageCount: u32, // >= 2
    ImageCount: u32, // >= MinImageCount
    MSAASamples: vk.Flags, // >= VK_SAMPLE_COUNT_1_BIT
    Allocator: ?*const vk.AllocationCallbacks,
    CheckVkResultFn: ?fn (vk.Result) callconv(vk.vulkan_call_conv) void,
};

const ImGuiContext = C.ImGuiContext;
const ImFontAtlas = C.ImFontAtlas;
const ImDrawData = C.ImDrawData;
const ImGuiIO = C.ImGuiIO;

pub extern fn ImGui_ImplGlfw_InitForOpenGL(window: *anyopaque, install_callbacks: bool) bool;
pub extern fn ImGui_ImplGlfw_Shutdown() void;
pub extern fn ImGui_ImplGlfw_NewFrame() void;
pub extern fn ImGui_ImplSDL2_InitForOpenGL(window: *anyopaque, install_callbacks: bool) bool;
pub extern fn ImGui_ImplSDL2_InitForVulkan(window: *anyopaque) bool;
pub extern fn ImGui_ImplSDL2_Shutdown() void;
pub extern fn ImGui_ImplSDL2_NewFrame() void;
pub extern fn ImGui_ImplSDL2_ProcessEvent(window: sdl.SDL_Event) void;
pub extern fn ImGui_ImplOpenGL3_Init(glsl_version: [*:0]const u8) bool;
pub extern fn ImGui_ImplOpenGL3_Shutdown() void;
pub extern fn ImGui_ImplOpenGL3_NewFrame() void;
pub extern fn ImGui_ImplOpenGL3_RenderDrawData(draw_data: *ImDrawData) void;
pub extern fn ImGui_ImplVulkan_Init(info: *const ImGui_ImplVulkan_InitInfo, render_pass: vk.RenderPass) bool;
pub extern fn ImGui_ImplVulkan_Shutdown() void;
pub extern fn ImGui_ImplVulkan_NewFrame() void;
pub extern fn ImGui_ImplVulkan_RenderDrawData(draw_data: *ImDrawData, command_buffer: vk.CommandBuffer, pipeline: vk.Pipeline) void;
pub extern fn ImGui_ImplVulkan_CreateFontsTexture(command_buffer: vk.CommandBuffer) bool;
pub extern fn ImGui_ImplVulkan_DestroyFontUploadObjects() void;
pub extern fn ImGui_ImplVulkan_SetMinImageCount(min_image_count: u32) void;
pub extern fn ImGui_ImplVulkan_LoadFunctions(loader_func: *const anyopaque, user_data: ?*const anyopaque) bool;
pub extern fn ImGui_ImplVulkan_AddTexture(sampler: vk.Sampler, image_view: vk.ImageView, image_layout: vk.ImageLayout) vk.DescriptorSet;

pub fn createContext(shared_font_atlas: ?*ImFontAtlas) !*ImGuiContext {
    const result = @ptrCast(?*C.ImGuiContext, C.igCreateContext(shared_font_atlas));
    return result orelse error.FailedToCreateImGuiContext;
}

pub fn showDemoWindow(open: *bool) void {
    C.igShowDemoWindow(open);
}

pub fn getDrawData() *ImDrawData {
    return C.igGetDrawData();
}

pub fn getIO() *ImGuiIO {
    return C.igGetIO();
}

pub fn renderPlatformWindowsDefault(platform_render_arg: ?*anyopaque, renderer_render_arg: ?*anyopaque) void {
    C.igRenderPlatformWindowsDefault(platform_render_arg, renderer_render_arg);
}

pub fn newFrame() void {
    ImGui_ImplVulkan_NewFrame();
    ImGui_ImplSDL2_NewFrame();
    C.igNewFrame();
}

pub fn endFrame() void {
    C.igEndFrame();
}

pub fn render() void {
    C.igRender();
}

pub fn updatePlatformWindows() void {
    var io = getIO();
    if ((io.ConfigFlags & (1 << 10)) != 0) {
        // const backup_current_window = sdl.SDL_GL_GetCurrentWindow();
        // const backup_current_context = sdl.SDL_GL_GetCurrentContext();
        C.igUpdatePlatformWindows();
        C.igRenderPlatformWindowsDefault(null, null);
        // _ = sdl.SDL_GL_MakeCurrent(backup_current_window, backup_current_context);
    }
}

pub fn dockspace() void {
    var io = getIO();

    var dockspaceFlags: c_int = 0;
    var windowFlags: c_int = C.ImGuiWindowFlags_NoDocking | C.ImGuiWindowFlags_NoTitleBar | C.ImGuiWindowFlags_NoTitleBar | C.ImGuiWindowFlags_NoCollapse | C.ImGuiWindowFlags_NoResize | C.ImGuiWindowFlags_NoMove | C.ImGuiWindowFlags_NoBringToFrontOnFocus | C.ImGuiWindowFlags_NoNavFocus;

    const viewport = @ptrCast(*C.ImGuiViewport, C.igGetMainViewport());
    C.igSetNextWindowPos(viewport.WorkPos, 0, .{ .x = 0, .y = 0 });
    C.igSetNextWindowSize(viewport.WorkSize, 0);
    C.igSetNextWindowViewport(viewport.ID);
    C.igPushStyleVar_Float(C.ImGuiStyleVar_WindowRounding, 0);
    C.igPushStyleVar_Float(C.ImGuiStyleVar_WindowBorderSize, 0);
    C.igPushStyleVar_Vec2(C.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    defer C.igPopStyleVar(3);

    var open = true;
    _ = C.igBegin("Dockspace", &open, windowFlags);

    if ((io.ConfigFlags & C.ImGuiConfigFlags_DockingEnable) != 0) {
        const id = C.igGetID_Str("Dockspace");
        _ = C.igDockSpace(id, .{ .x = 0, .y = 0 }, dockspaceFlags, null);
    }

    C.igEnd();
}

pub fn property(name: []const u8) void {
    imgui.Text("%.*s: ", name.len, name.ptr);
    imgui.SameLine();
}

pub fn any(value: anytype, name: []const u8) void {
    imgui.PushIDInt64(@ptrToInt(value));
    defer imgui.PopID();

    const typeInfoOuter = @typeInfo(@TypeOf(value));

    const actualType = typeInfoOuter.Pointer.child;

    if (comptime std.meta.trait.hasFn("imguiDetails")(actualType)) {
        return value.imguiDetails();
    }

    // Special case: string
    if (actualType == []const u8) {
        property(name);
        imgui.Text("%.*s", value.*.len, value.*.ptr);
        return;
    }

    const typeInfo = @typeInfo(actualType);
    switch (typeInfo) {
        .Int => |ti| {
            const dataType: imgui.DataType = blk: {
                if (ti.signedness == .signed) {
                    switch (ti.bits) {
                        8 => break :blk .S8,
                        16 => break :blk .S16,
                        32 => break :blk .S32,
                        64 => break :blk .S64,
                        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(actualType))),
                    }
                } else {
                    switch (ti.bits) {
                        8 => break :blk .U8,
                        16 => break :blk .U16,
                        32 => break :blk .U32,
                        64 => break :blk .U64,
                        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(actualType))),
                    }
                }
            };

            property(name);
            _ = imgui.DragScalarExt("", dataType, value, 1, null, null, null, (imgui.SliderFlags{ .NoRoundToFormat = true, .AlwaysClamp = true }).toInt());
        },

        .Float => |ti| {
            const dataType: imgui.DataType = blk: {
                switch (ti.bits) {
                    32 => break :blk .Float,
                    64 => break :blk .Double,
                    else => @compileError("Unsupported type " ++ @typeName(@TypeOf(actualType))),
                }
            };

            property(name);
            _ = imgui.DragScalar("", dataType, value, 1);
        },

        .Bool => {
            property(name);
            _ = imgui.Checkbox("", value);
        },

        .Struct => |ti| {
            const flags = imgui.TreeNodeFlags{ .Bullet = true, .SpanFullWidth = false, .DefaultOpen = true };
            if (imgui.TreeNodeExPtr(value, flags.toInt(), "")) {
                defer imgui.TreePop();
                inline for (ti.fields) |field| {
                    any(&@field(value, field.name), field.name);
                }
            }
        },

        .Pointer => |ti| {
            switch (ti.size) {
                .Slice => {
                    @compileLog(typeInfo);
                    @compileError("Can't display value of type " ++ @typeName(actualType));
                },

                else => {
                    @compileLog(typeInfo);
                    @compileError("Can't display value of type " ++ @typeName(actualType));
                },
            }
        },

        else => {
            @compileLog(typeInfo);
            @compileError("Can't display value of type " ++ @typeName(actualType));
        },
    }
}

pub fn anyDynamic(typeInfo: *const Rtti.TypeInfo, value: []u8) void {
    imgui.PushIDInt64(@ptrToInt(value.ptr));
    defer imgui.PopID();

    // Special case: string
    if (typeInfo == Rtti.typeInfo([]const u8)) {
        const string = @ptrCast(*[]const u8, @alignCast(@alignOf(*u8), value.ptr)).*;
        imgui.Text("%.*s", string.len, string.ptr);
        return;
    }

    switch (typeInfo.kind) {
        .Int => |ti| {
            const dataType: imgui.DataType = blk: {
                if (ti.signedness == .signed) {
                    switch (ti.bits) {
                        8 => break :blk .S8,
                        16 => break :blk .S16,
                        32 => break :blk .S32,
                        64 => break :blk .S64,
                        else => unreachable,
                    }
                } else {
                    switch (ti.bits) {
                        8 => break :blk .U8,
                        16 => break :blk .U16,
                        32 => break :blk .U32,
                        64 => break :blk .U64,
                        else => unreachable,
                    }
                }
            };

            _ = imgui.DragScalarExt("", dataType, value.ptr, 1, null, null, null, (imgui.SliderFlags{ .NoRoundToFormat = true, .AlwaysClamp = true }).toInt());
        },

        .Float => |ti| {
            const dataType: imgui.DataType = blk: {
                switch (ti.bits) {
                    32 => break :blk .Float,
                    64 => break :blk .Double,
                    else => unreachable,
                }
            };

            _ = imgui.DragScalar("", dataType, value.ptr, 1);
        },

        .Bool => {
            _ = imgui.Checkbox("", @ptrCast(*bool, value.ptr));
        },

        .Struct => |ti| {
            var tableFlags = imgui.TableFlags{
                .Resizable = true,
                .RowBg = true,
            };
            if (imgui.BeginTable("ComponentData", 2, tableFlags, .{}, 0)) {
                defer imgui.EndTable();

                for (ti.fields) |field| {
                    imgui.TableNextRow(.{}, 0);
                    _ = imgui.TableSetColumnIndex(0);
                    imgui.Text("%.*s", field.name.len, field.name.ptr);

                    _ = imgui.TableSetColumnIndex(1);
                    anyDynamic(
                        field.field_type,
                        value[field.offset..(field.offset + field.field_type.size)],
                    );
                }
            }
        },

        .Pointer => |ti| {
            switch (ti.size) {
                .Slice => {},

                else => {},
            }
        },

        else => {},
    }
}
