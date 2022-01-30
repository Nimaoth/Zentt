const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zentt", "src/main.zig");

    // opengl
    exe.addPackagePath("zgl", "libs/zgl/zgl.zig");
    exe.linkSystemLibrary("epoxy");

    // sdl2
    exe.linkSystemLibrary("SDL2");

    // imgui
    exe.addIncludeDir("libs/cimgui");
    exe.addIncludeDir("libs/cimgui/imgui");
    exe.addCSourceFiles(
        &.{
            "libs/cimgui/cimgui.cpp",
            "libs/cimgui/imgui/imgui.cpp",
            "libs/cimgui/imgui/imgui_demo.cpp",
            "libs/cimgui/imgui/imgui_draw.cpp",
            "libs/cimgui/imgui/imgui_tables.cpp",
            "libs/cimgui/imgui/imgui_widgets.cpp",
            "libs/cimgui/imgui/backends/imgui_impl_sdl.cpp",
            "libs/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
        },
        &.{
            "-Wall",
            "-fno-exceptions",
            "-fno-rtti",
            "-fno-threadsafe-statics",
            "-DIMGUI_IMPL_OPENGL_LOADER_CUSTOM",
            "-DIMGUI_IMPL_OPENGL_EPOXY",
            "-DIMGUI_IMPL_API=extern\"C\"",
        },
    );

    exe.linkLibC();
    exe.linkLibCpp();
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
