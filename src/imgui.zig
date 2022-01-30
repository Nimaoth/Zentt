const std = @import("std");

const C = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
});

const sdl = @import("sdl.zig");

pub extern fn ImGui_ImplGlfw_InitForOpenGL(window: *anyopaque, install_callbacks: bool) bool;
pub extern fn ImGui_ImplGlfw_Shutdown() void;
pub extern fn ImGui_ImplGlfw_NewFrame() void;
pub extern fn ImGui_ImplSDL2_InitForOpenGL(window: *anyopaque, install_callbacks: bool) bool;
pub extern fn ImGui_ImplSDL2_Shutdown() void;
pub extern fn ImGui_ImplSDL2_NewFrame() void;
pub extern fn ImGui_ImplSDL2_ProcessEvent(window: sdl.SDL_Event) void;
pub extern fn ImGui_ImplOpenGL3_Init(glsl_version: [*:0]const u8) bool;
pub extern fn ImGui_ImplOpenGL3_Shutdown() void;
pub extern fn ImGui_ImplOpenGL3_NewFrame() void;
pub extern fn ImGui_ImplOpenGL3_RenderDrawData(draw_data: *ImDrawData) void;

const ImGuiContext = C.ImGuiContext;
const ImFontAtlas = C.ImFontAtlas;
const ImDrawData = C.ImDrawData;
const ImGuiIO = C.ImGuiIO;

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
    ImGui_ImplOpenGL3_NewFrame();
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
        const backup_current_window = sdl.SDL_GL_GetCurrentWindow();
        const backup_current_context = sdl.SDL_GL_GetCurrentContext();
        C.igUpdatePlatformWindows();
        C.igRenderPlatformWindowsDefault(null, null);
        _ = sdl.SDL_GL_MakeCurrent(backup_current_window, backup_current_context);
    }
}

pub fn dockspace() void {
    var io = getIO();

    var dockspaceFlags: c_int = 0;
    var windowFlags: c_int = C.ImGuiWindowFlags_NoDocking | C.ImGuiWindowFlags_NoTitleBar | C.ImGuiWindowFlags_NoTitleBar | C.ImGuiWindowFlags_NoCollapse | C.ImGuiWindowFlags_NoResize | C.ImGuiWindowFlags_NoMove | C.ImGuiWindowFlags_NoBringToFrontOnFocus | C.ImGuiWindowFlags_NoNavFocus;

    const viewport = @ptrCast(*C.ImGuiViewport, C.igGetMainViewport());
    C.igSetNextWindowPos(viewport.WorkPos, 0, .{.x = 0, .y = 0});
    C.igSetNextWindowSize(viewport.WorkSize, 0);
    C.igSetNextWindowViewport(viewport.ID);
    C.igPushStyleVar_Float(C.ImGuiStyleVar_WindowRounding, 0);
    C.igPushStyleVar_Float(C.ImGuiStyleVar_WindowBorderSize, 0);
    C.igPushStyleVar_Vec2(C.ImGuiStyleVar_WindowPadding, .{.x = 0, .y = 0});
    defer C.igPopStyleVar(3);

    var open = true;
    _ = C.igBegin("Dockspace", &open, windowFlags);

    if ((io.ConfigFlags & C.ImGuiConfigFlags_DockingEnable) != 0) {
        const id = C.igGetID_Str("Dockspace");
        _ = C.igDockSpace(id, .{ .x = 0, .y = 0 }, dockspaceFlags, null);
    }

    C.igEnd();
}
