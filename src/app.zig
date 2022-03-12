const std = @import("std");
const vk = @import("vulkan");

const imgui = @import("editor/imgui.zig");
const imgui2 = @import("editor/imgui2.zig");

const sdl = @import("rendering/sdl.zig");

const Allocator = std.mem.Allocator;

const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Renderer = @import("rendering/renderer.zig");
const SpriteRenderer = @import("rendering/sprite_renderer.zig");

const Profiler = @import("editor/profiler.zig");

const Self = @This();

allocator: std.mem.Allocator,

isRunning: bool,

window: *sdl.SDL_Window,
renderer: *Renderer,
sprite_renderer: *SpriteRenderer,
profiler: Profiler,

windowSize: vk.Extent2D,

matrices: SpriteRenderer.SceneMatricesUbo,

pub fn init(allocator: std.mem.Allocator) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    var extent = vk.Extent2D{ .width = 1280, .height = 720 };

    // Create our window
    const window = sdl.SDL_CreateWindow(
        "My Game Window",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        @intCast(c_int, extent.width),
        @intCast(c_int, extent.height),
        sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_SHOWN | sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_MAXIMIZED,
    ) orelse {
        sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };

    var renderer = try Renderer.init(allocator, window, extent);
    errdefer renderer.deinit();

    var sprite_renderer = try SpriteRenderer.init(allocator, &renderer.gc, renderer.swapchain.swap_images.len, renderer.sceneRenderPass);
    errdefer sprite_renderer.deinit();

    try imgui2.initForWindow(window);
    errdefer imgui2.deinitWindow();

    try imgui2.initForRenderer(renderer);
    errdefer imgui2.deinitRenderer(renderer);

    self.* = Self{
        .allocator = allocator,
        .isRunning = true,
        .window = window,
        .renderer = renderer,
        .sprite_renderer = sprite_renderer,
        .profiler = Profiler.init(allocator),
        .windowSize = extent,
        .matrices = .{
            .view = Mat4.identity(),
            .proj = Mat4.orthographic(-100, 100, -100, 100, 1, -1),
        },
    };
    return self;
}

pub fn deinit(self: *Self) void {
    self.waitIdle();

    imgui2.deinitRenderer(self.renderer);
    imgui2.deinitWindow();
    self.profiler.deinit();
    self.sprite_renderer.deinit();
    self.renderer.deinit();
    sdl.SDL_DestroyWindow(self.window);
    sdl.SDL_Quit();

    self.allocator.destroy(self);
}

pub fn waitIdle(self: *Self) void {
    self.renderer.gc.vkd.queueWaitIdle(self.renderer.gc.graphics_queue.handle) catch |err| {
        std.log.err("Failed to wait for idle device: {}", .{err});
    };
}

pub fn beginFrame(self: *Self) !void {
    var w: c_int = undefined;
    var h: c_int = undefined;
    sdl.SDL_Vulkan_GetDrawableSize(self.window, &w, &h);
    self.windowSize.width = @intCast(u32, w);
    self.windowSize.height = @intCast(u32, h);

    {
        const scope = self.profiler.beginScope("prepare + demo");
        defer scope.end();
        try self.renderer.swapchain.prepare();

        imgui2.newFrame();
        imgui2.dockspace();
    }
}

pub fn endFrame(self: *Self) !void {
    const scope = self.profiler.beginScope("App.endFrame");
    defer scope.end();

    imgui2.render();
    imgui2.endFrame();

    try self.renderer.beginMainRender();
    imgui2.ImGui_ImplVulkan_RenderDrawData(imgui2.getDrawData(), self.renderer.getCommandBuffer(), .null_handle);
    imgui2.updatePlatformWindows();
    try self.renderer.endMainRender(self.windowSize);
}

pub fn beginRender(self: *Self) !void {
    const contentSize = blk: {
        imgui.PushStyleVarVec2(.WindowPadding, .{});
        defer imgui.PopStyleVar();

        const open = imgui.Begin("Viewport");
        defer imgui.End();

        const size = imgui.GetContentRegionAvail();

        const aspect_ratio = size.x / size.y;
        const height = imgui2.variable(endFrame, f32, "Camera Size", 500, true, .{ .min = 1, .max = 1000, .speed = 0.01 }).*;

        self.matrices.proj = Mat4.orthographic(-height * aspect_ratio * 0.5, height * aspect_ratio * 0.5, -height * 0.5, height * 0.5, 1, -1);
        if (open) {
            imgui.ImageExt(
                @ptrCast(**anyopaque, &self.renderer.getSceneImage().descriptor).*,
                size,
                .{ .x = 0, .y = 0 },
                .{ .x = size.x / 1920, .y = size.y / 1080 }, // the size is the size of the scene frame buffer which doesn't get resized.
                .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                .{ .x = 0, .y = 0, .z = 0, .w = 0 },
            );
        }

        break :blk size;
    };

    const frame = try self.renderer.beginSceneRender(
        .{ .width = @floatToInt(u32, std.math.max(contentSize.x, 1)), .height = @floatToInt(u32, std.math.max(contentSize.y, 1)) },
    );

    // const hdr = imgui2.variable(endFrame, bool, "HDR", true, true, .{}).*;
    // const options = struct { color: bool = true, flags: imgui.ColorEditFlags }{ .flags = .{ .HDR = hdr } };
    // const color = imgui2.variable(endFrame, Vec4, "Tint", .{ .data = [4]f32{ 1, 1, 0, 1 } }, true, options).*;
    // const transform = imgui2.variable(endFrame, Vec4, "Transform", .{ .data = [4]f32{ 0, 0, 1, 1 } }, true, .{}).*;
    try self.sprite_renderer.beginRender(frame.cmdbuf, frame.frame_index, &self.matrices);
}

pub fn endRender(self: *Self) !void {
    self.sprite_renderer.endRender();
    try self.renderer.endSceneRender();
}
