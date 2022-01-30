const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub usingnamespace c;

pub const Window = struct {
    const Self = @This();

    handle: *c.SDL_Window,

    pub fn init() !@This() {
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, 0);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 0);
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
            c.SDL_WINDOW_OPENGL,
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
