const std = @import("std");
const vk = @import("vulkan");
const c = @import("vulkan/c.zig");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const sdl = @import("sdl.zig");

const Vec2 = imgui.Vec2;
const Allocator = std.mem.Allocator;

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const resources = @import("resources");

const app_name = "vulkan-zig triangle example";
const Renderer = @import("renderer.zig");
const Details = @import("details_window.zig");

const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;
const Tag = @import("tag_component.zig").Tag;
const Commands = @import("commands.zig");
const Profiler = @import("profiler.zig");

const Self = @This();

allocator: std.mem.Allocator,

isRunning: bool,

window: *sdl.SDL_Window,
renderer: *Renderer,
profiler: Profiler,

windowSize: vk.Extent2D,

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

    try imgui2.initForWindow(window);
    errdefer imgui2.deinitWindow();

    try imgui2.initForRenderer(renderer);
    errdefer imgui2.deinitRenderer(renderer);

    self.* = Self{
        .allocator = allocator,
        .isRunning = true,
        .window = window,
        .renderer = renderer,
        .profiler = Profiler.init(allocator),
        .windowSize = extent,
    };
    return self;
}

pub fn deinit(self: *Self) void {
    self.renderer.waitIdle();

    imgui2.deinitRenderer(self.renderer);
    imgui2.deinitWindow();
    self.profiler.deinit();
    self.renderer.deinit();
    sdl.SDL_DestroyWindow(self.window);
    sdl.SDL_Quit();

    self.allocator.destroy(self);
}

pub fn beginFrame(self: *Self) !void {
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event) != 0) {
        _ = imgui2.ImGui_ImplSDL2_ProcessEvent(event);
        switch (event.@"type") {
            sdl.SDL_QUIT => {
                self.isRunning = false;
            },
            else => {},
        }
    }

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

    try self.renderer.beginRender();
    imgui2.ImGui_ImplVulkan_RenderDrawData(imgui2.getDrawData(), self.renderer.getCommandBuffer(), .null_handle);
    imgui2.updatePlatformWindows();
    try self.renderer.endRender(self.windowSize);
}
