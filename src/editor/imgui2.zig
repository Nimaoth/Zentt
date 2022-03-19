const std = @import("std");
const vk = @import("vulkan");

const C = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
});

const imgui = @import("imgui.zig");
const imguizmo = @import("imguizmo.zig");
const sdl = @import("../rendering/sdl.zig");

const Renderer = @import("../rendering/renderer.zig");
const AssetDB = @import("../rendering/assetdb.zig");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

const Rtti = @import("../util/rtti.zig");

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

    imguizmo.BeginFrame();
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

var descriptor_pool: vk.DescriptorPool = .null_handle;

pub fn initForWindow(window: *sdl.SDL_Window) !void {
    _ = imgui.CreateContext();
    var io = imgui.GetIO();
    io.ConfigFlags = io.ConfigFlags.with(.{ .DockingEnable = true, .ViewportsEnable = true });
    _ = ImGui_ImplSDL2_InitForVulkan(window);
}

export fn vulkan_loader(function_name: [*:0]const u8, user_data: ?*anyopaque) vk.PfnVoidFunction {
    const instance = @ptrCast(*vk.Instance, @alignCast(@alignOf(vk.Instance), user_data orelse unreachable)).*;
    return sdl.SDL_Vulkan_GetVkGetInstanceProcAddrZig()(instance, function_name);
}

export fn check_vk_result(err: vk.Result) callconv(vk.vulkan_call_conv) void {
    if (err != .success) {
        std.log.err("check_vk_result: {}", .{err});
    }
}

pub fn initForRenderer(renderer: *Renderer) !void {
    const POOL_SIZE = 1000;
    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{ .@"type" = .sampler, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .combined_image_sampler, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .sampled_image, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .storage_image, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .uniform_texel_buffer, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .storage_texel_buffer, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .uniform_buffer, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .storage_buffer, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .uniform_buffer_dynamic, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .storage_buffer_dynamic, .descriptor_count = POOL_SIZE },
        .{ .@"type" = .input_attachment, .descriptor_count = POOL_SIZE },
    };
    const pool_info = vk.DescriptorPoolCreateInfo{
        .flags = vk.DescriptorPoolCreateFlags{ .free_descriptor_set_bit = true },
        .max_sets = POOL_SIZE * pool_sizes.len,
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
    };
    descriptor_pool = try renderer.gc.vkd.createDescriptorPool(renderer.gc.dev, &pool_info, null);
    errdefer renderer.gc.vkd.destroyDescriptorPool(renderer.gc.dev, descriptor_pool, null);

    {
        var instance = renderer.gc.instance;
        if (!ImGui_ImplVulkan_LoadFunctions(vulkan_loader, &instance)) {
            return error.ImguiFailedToLoadVulkanFunctions;
        }
    }

    const info = ImGui_ImplVulkan_InitInfo{
        .Instance = renderer.gc.instance,
        .PhysicalDevice = renderer.gc.pdev,
        .Device = renderer.gc.dev,
        .QueueFamily = renderer.gc.graphics_queue.family,
        .Queue = renderer.gc.graphics_queue.handle,
        .PipelineCache = null,
        .DescriptorPool = descriptor_pool,
        .Subpass = 0,
        .MinImageCount = @intCast(u32, renderer.swapchain.swap_images.len),
        .ImageCount = @intCast(u32, renderer.swapchain.swap_images.len),
        .MSAASamples = (vk.SampleCountFlags{ .@"1_bit" = true }).toInt(),
        .Allocator = null,
        .CheckVkResultFn = check_vk_result,
    };
    _ = ImGui_ImplVulkan_Init(&info, renderer.mainRenderPass);
    errdefer ImGui_ImplVulkan_Shutdown();

    // Upload Fonts
    {
        // Use any command queue
        var cmdbuf: vk.CommandBuffer = undefined;

        try renderer.gc.vkd.allocateCommandBuffers(renderer.gc.dev, &.{
            .command_pool = renderer.commandPool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast([*]vk.CommandBuffer, &cmdbuf));
        defer renderer.gc.vkd.freeCommandBuffers(renderer.gc.dev, renderer.commandPool, 1, @ptrCast([*]const vk.CommandBuffer, &cmdbuf));

        try renderer.gc.vkd.beginCommandBuffer(cmdbuf, &.{
            .flags = .{ .one_time_submit_bit = true },
            .p_inheritance_info = null,
        });

        if (!ImGui_ImplVulkan_CreateFontsTexture(cmdbuf)) {
            return error.ImguiFailedToCreateFontsTexture;
        }
        defer ImGui_ImplVulkan_DestroyFontUploadObjects();

        try renderer.gc.vkd.endCommandBuffer(cmdbuf);

        const si = vk.SubmitInfo{
            .wait_semaphore_count = 0,
            .p_wait_semaphores = undefined,
            .p_wait_dst_stage_mask = undefined,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &cmdbuf),
            .signal_semaphore_count = 0,
            .p_signal_semaphores = undefined,
        };
        try renderer.gc.vkd.queueSubmit(renderer.gc.graphics_queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &si), .null_handle);
        try renderer.gc.vkd.queueWaitIdle(renderer.gc.graphics_queue.handle);
    }
}

pub fn deinitWindow() void {
    ImGui_ImplSDL2_Shutdown();
}

pub fn deinitRenderer(renderer: *Renderer) void {
    renderer.gc.vkd.destroyDescriptorPool(renderer.gc.dev, descriptor_pool, null);
    ImGui_ImplVulkan_Shutdown();
}

pub fn property(name: []const u8) void {
    imgui.Text("%.*s: ", name.len, name.ptr);
    imgui.SameLine();
}

// fn getOr(options: anytype, comptime field: anytype, default: anytype) void {
//     _ = default;
//     _ = options;
//     std.log.info("{s}", .{@tagName(field)});
// }

fn getOrReturnType(comptime Options: type, comptime field: anytype, comptime Default: type) type {
    if (@hasField(Options, @tagName(field))) {
        return std.meta.fieldInfo(Options, field).field_type;
    } else {
        return Default;
    }
}

fn getOr(options: anytype, comptime field: anytype, comptime default: anytype) getOrReturnType(@TypeOf(options), field, @TypeOf(default)) {
    if (@hasField(@TypeOf(options), @tagName(field))) {
        return @field(options, @tagName(field));
    } else {
        return default;
    }
}

fn getOrPtrNull(comptime T: type, options: anytype, comptime field: anytype) ?*anyopaque {
    if (@hasField(@TypeOf(options.*), @tagName(field))) {
        const Scope = struct {
            var x: T = undefined;
        };
        Scope.x = @field(options.*, @tagName(field));
        return &Scope.x;
    } else {
        return null;
    }
}

pub fn any(value: anytype, name: []const u8, options: anytype) void {
    imgui.PushIDInt64(@ptrToInt(value));
    defer imgui.PopID();

    const typeInfoOuter = @typeInfo(@TypeOf(value));

    const ValueType = typeInfoOuter.Pointer.child;

    if (comptime std.meta.trait.hasFn("imguiDetails")(ValueType)) {
        return value.imguiDetails();
    }

    // Special case: string
    if (ValueType == []const u8) {
        property(name);
        imgui.Text("%.*s", value.*.len, value.*.ptr);
        return;
    }

    if (ValueType == Vec4) {
        property(name);
        const as_color = getOr(options, .color, false);
        if (as_color) {
            const flags = getOr(options, .flags, imgui.ColorEditFlags{});
            var as_array = value.toArray();
            if (imgui.ColorEdit4Ext("", &as_array, flags)) {
                value.* = Vec4.fromSlice(as_array[0..]);
            }
        } else {
            const speed = getOr(options, .speed, @floatCast(f32, 1.0));
            const min = getOr(options, .min, @floatCast(f32, 0.0));
            const max = getOr(options, .max, @floatCast(f32, 0.0));

            var as_array = value.toArray();
            if (imgui.DragFloat4Ext("", &as_array, speed, min, max, "%.3f", .{})) {
                value.* = Vec4.fromSlice(as_array[0..]);
            }
        }
        return;
    }

    if (ValueType == Vec3) {
        property(name);
        const as_color = getOr(options, .color, false);
        if (as_color) {
            const flags = getOr(options, .flags, imgui.ColorEditFlags{});
            var as_array = value.toArray();
            if (imgui.ColorEdit3Ext("", &as_array, flags)) {
                value.* = Vec3.fromSlice(as_array[0..]);
            }
        } else {
            const speed = getOr(options, .speed, @floatCast(f32, 1.0));
            const min = getOr(options, .min, @floatCast(f32, 0.0));
            const max = getOr(options, .max, @floatCast(f32, 0.0));

            var as_array = value.toArray();
            if (imgui.DragFloat3Ext("", &as_array, speed, min, max, "%.3f", .{})) {
                value.* = Vec3.fromSlice(as_array[0..]);
            }
        }
        return;
    }

    if (ValueType == Vec2) {
        property(name);
        const speed = getOr(options, .speed, @floatCast(f32, 1.0));
        const min = getOr(options, .min, @floatCast(f32, 0.0));
        const max = getOr(options, .max, @floatCast(f32, 0.0));

        var as_array = value.toArray();
        if (imgui.DragFloat2Ext("", &as_array, speed, min, max, "%.3f", .{})) {
            value.* = Vec2.fromSlice(as_array[0..]);
        }
        return;
    }

    if (ValueType == imgui.Vec4) {
        property(name);
        const as_color = getOr(options, .color, false);
        if (as_color) {
            const flags = getOr(options, .flags, imgui.ColorEditFlags{});
            var as_array = @ptrCast(*[4]f32, value);
            _ = imgui.ColorEdit4Ext("", as_array, flags);
        } else {
            const speed = getOr(options, .speed, @floatCast(f32, 1.0));
            const min = getOr(options, .min, @floatCast(f32, 0.0));
            const max = getOr(options, .max, @floatCast(f32, 0.0));

            var as_array = @ptrCast(*[4]f32, value);
            _ = imgui.DragFloat4Ext("", as_array, speed, min, max, "%.3f", .{});
        }
        return;
    }

    const typeInfo = @typeInfo(ValueType);
    switch (typeInfo) {
        .Int => |ti| {
            const dataType: imgui.DataType = blk: {
                if (ti.signedness == .signed) {
                    switch (ti.bits) {
                        8 => break :blk .S8,
                        16 => break :blk .S16,
                        32 => break :blk .S32,
                        64 => break :blk .S64,
                        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(ValueType))),
                    }
                } else {
                    switch (ti.bits) {
                        8 => break :blk .U8,
                        16 => break :blk .U16,
                        32 => break :blk .U32,
                        64 => break :blk .U64,
                        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(ValueType))),
                    }
                }
            };

            property(name);

            const speed = getOr(options, .speed, @floatCast(f32, 1.0));
            const min = getOrPtrNull(ValueType, &options, .min);
            const max = getOrPtrNull(ValueType, &options, .max);
            _ = imgui.DragScalarExt("", dataType, value, speed, min, max, null, (imgui.SliderFlags{ .NoRoundToFormat = true, .AlwaysClamp = true }).toInt());
        },

        .Float => |ti| {
            const dataType: imgui.DataType = blk: {
                switch (ti.bits) {
                    32 => break :blk .Float,
                    64 => break :blk .Double,
                    else => @compileError("Unsupported type " ++ @typeName(@TypeOf(ValueType))),
                }
            };

            const speed = getOr(options, .speed, @floatCast(f32, 1.0));
            const min = getOrPtrNull(ValueType, &options, .min);
            const max = getOrPtrNull(ValueType, &options, .max);
            property(name);
            _ = imgui.DragScalarExt("", dataType, value, speed, min, max, null, imgui.SliderFlags.None.toInt());
        },

        .Bool => {
            property(name);
            _ = imgui.Checkbox("", value);
        },

        .Enum => |ti| {
            _ = ti;
            const tag_name = std.meta.tagName(value.*);
            any(&tag_name, name, options);
        },

        .Struct => |ti| {
            const flags = imgui.TreeNodeFlags{ .Bullet = true, .SpanFullWidth = false, .DefaultOpen = true };
            if (imgui.TreeNodeExPtr(value, flags.toInt(), "")) {
                defer imgui.TreePop();
                inline for (ti.fields) |field| {
                    any(&@field(value, field.name), field.name, .{});
                }
            }
        },

        .Pointer => |ti| {
            switch (ti.size) {
                .Slice => {
                    @compileLog(typeInfo);
                    @compileError("Can't display value of type " ++ @typeName(ValueType));
                },

                else => {
                    @compileLog(typeInfo);
                    @compileError("Can't display value of type " ++ @typeName(ValueType));
                },
            }
        },

        else => {
            @compileLog(typeInfo);
            @compileError("Can't display value of type " ++ @typeName(ValueType));
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
    if (typeInfo == Rtti.typeInfo([:0]const u8)) {
        const string = @ptrCast(*[:0]const u8, @alignCast(@alignOf(*u8), value.ptr)).*;
        imgui.Text("%s", string.ptr);
        return;
    }

    if (typeInfo == Rtti.typeInfo([]usize)) {
        const entities = @ptrCast(*[]usize, @alignCast(@alignOf(*usize), value.ptr)).*;
        for (entities) |e| {
            var x = e;
            anyDynamic(Rtti.typeInfo(usize), std.mem.asBytes(&x)[0..]);
        }
        return;
    }

    if (typeInfo == Rtti.typeInfo(*AssetDB.SpriteAnimationAsset)) {
        const asset = @ptrCast(**AssetDB.SpriteAnimationAsset, @alignCast(@alignOf(*u8), value.ptr)).*;
        anyDynamic(Rtti.typeInfo(AssetDB.SpriteAnimationAsset), std.mem.asBytes(asset));
        return;
    }

    if (typeInfo == Rtti.typeInfo(*AssetDB.TextureAsset)) {
        const asset = @ptrCast(**AssetDB.TextureAsset, @alignCast(@alignOf(*u8), value.ptr)).*;
        anyDynamic(Rtti.typeInfo(AssetDB.TextureAsset), std.mem.asBytes(asset));
        return;
    }

    if (typeInfo == Rtti.typeInfo(Vec4)) {
        const vec = @ptrCast(*Vec4, @alignCast(@alignOf(Vec4), value.ptr));
        // const as_color = getOr(options, .color, false);
        // if (as_color) {
        //     const flags = getOr(options, .flags, imgui.ColorEditFlags{});
        //     var as_array = value.toArray();
        //     if (imgui.ColorEdit4Ext("", &as_array, flags)) {
        //         value.* = Vec4.fromSlice(as_array[0..]);
        //     }
        // } else {
        // const speed = getOr(options, .speed, @floatCast(f32, 1.0));
        // const min = getOr(options, .min, @floatCast(f32, 0.0));
        // const max = getOr(options, .max, @floatCast(f32, 0.0));
        const speed: f32 = 1;
        const min: f32 = 1;
        const max: f32 = 1;

        var as_array = vec.toArray();
        if (imgui.DragFloat4Ext("", &as_array, speed, min, max, "%.3f", .{})) {
            vec.* = Vec4.fromSlice(as_array[0..]);
        }
        // }
        return;
    }

    if (typeInfo == Rtti.typeInfo(Vec3)) {
        const vec = @ptrCast(*Vec3, @alignCast(@alignOf(Vec3), value.ptr));

        // const as_color = getOr(options, .color, false);
        // if (as_color) {
        //     const flags = getOr(options, .flags, imgui.ColorEditFlags{});
        //     var as_array = value.toArray();
        //     if (imgui.ColorEdit3Ext("", &as_array, flags)) {
        //         value.* = Vec3.fromSlice(as_array[0..]);
        //     }
        // } else {
        // const speed = getOr(options, .speed, @floatCast(f32, 1.0));
        // const min = getOr(options, .min, @floatCast(f32, 0.0));
        // const max = getOr(options, .max, @floatCast(f32, 0.0));
        const speed: f32 = 1;
        const min: f32 = 1;
        const max: f32 = 1;

        var as_array = vec.toArray();
        if (imgui.DragFloat3Ext("", &as_array, speed, min, max, "%.3f", .{})) {
            vec.* = Vec3.fromSlice(as_array[0..]);
        }
        // }
        return;
    }

    if (typeInfo == Rtti.typeInfo(Vec2)) {
        const vec = @ptrCast(*Vec2, @alignCast(@alignOf(Vec2), value.ptr));
        // const speed = getOr(options, .speed, @floatCast(f32, 1.0));
        // const min = getOr(options, .min, @floatCast(f32, 0.0));
        // const max = getOr(options, .max, @floatCast(f32, 0.0));
        const speed: f32 = 1;
        const min: f32 = 1;
        const max: f32 = 1;

        var as_array = vec.toArray();
        if (imgui.DragFloat2Ext("", &as_array, speed, min, max, "%.3f", .{})) {
            vec.* = Vec2.fromSlice(as_array[0..]);
        }
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
                .Slice => {
                    const slice = @ptrCast(*[]u8, @alignCast(@alignOf(*u8), value.ptr)).*;
                    var bytes = slice;
                    bytes.len *= ti.child.size;

                    imgui.PushIDPtr(value.ptr);
                    defer imgui.PopID();

                    const open = imgui.CollapsingHeaderBoolPtrExt(
                        "Array",
                        null,
                        imgui.TreeNodeFlags.CollapsingHeader.with(.{ .DefaultOpen = true, .AllowItemOverlap = true }).without(.{ .Framed = true }),
                    );

                    if (open) {
                        var i: usize = 0;
                        while (i < bytes.len) : (i += ti.child.size) {
                            const element = bytes[i..(i + ti.child.size)];
                            anyDynamic(ti.child, element);
                        }
                    }
                },

                else => {},
            }
        },

        else => {},
    }
}

pub fn variable(comptime scope: anytype, comptime T: type, comptime name: []const u8, comptime defaultValue: T, editable: bool, options: anytype) *T {
    _ = scope;
    _ = name;
    const Scope = struct {
        var staticVar: T = defaultValue;
    };
    if (editable) {
        _ = imgui.Begin("Variables");
        any(&Scope.staticVar, name, options);
        imgui.End();
    }
    return &Scope.staticVar;
}
