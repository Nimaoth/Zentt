const c = @cImport({
    @cInclude("SDL.h");
});

pub usingnamespace c;

const vk = @import("vulkan");

pub const Window = struct {
    const Self = @This();

    handle: *c.SDL_Window,

    pub fn init() !@This() {
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, 0);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 6);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_STENCIL_SIZE, 8);

        // Create our window
        const window = c.SDL_CreateWindow(
            "My Game Window",
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            1280,
            720,
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_MAXIMIZED,
        ) orelse {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        return @This(){
            .handle = window,
        };
    }

    pub fn deinit(self: *const Self) void {
        c.SDL_DestroyWindow(self.handle);
    }

    pub fn makeContextCurrent(self: *const Self) void {
        const context = c.SDL_GL_CreateContext(self.handle);
        _ = c.SDL_GL_MakeCurrent(self.handle, context);
    }

    pub fn swapBuffers(self: *const Self) void {
        c.SDL_GL_SwapWindow(self.handle);
    }
};

pub extern fn SDL_Vulkan_GetDrawableSize(window: *c.SDL_Window, w: *c_int, h: *c_int) void;
pub extern fn SDL_Vulkan_CreateSurface(window: *c.SDL_Window, instance: vk.Instance, surface: *vk.SurfaceKHR) c.SDL_bool;
pub extern fn SDL_Vulkan_GetInstanceExtensions(window: *c.SDL_Window, pCount: *u32, pNames: ?[*][*:0]const u8) c.SDL_bool;
pub extern fn SDL_Vulkan_GetVkGetInstanceProcAddr() vk.PfnVoidFunction;
pub fn SDL_Vulkan_GetVkGetInstanceProcAddrZig() fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction {
    return @ptrCast(fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction, SDL_Vulkan_GetVkGetInstanceProcAddr());
}
