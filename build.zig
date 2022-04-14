const std = @import("std");
const vkgen = @import("generator/index.zig");
const Step = std.build.Step;
const Builder = std.build.Builder;

pub const ResourceGenStep = struct {
    step: Step,
    shader_step: *vkgen.ShaderCompileStep,
    builder: *Builder,
    package: std.build.Pkg,
    output_file: std.build.GeneratedFile,
    resources: std.ArrayList(u8),

    pub fn init(builder: *Builder, out: []const u8) *ResourceGenStep {
        const self = builder.allocator.create(ResourceGenStep) catch unreachable;
        const full_out_path = std.fs.path.join(builder.allocator, &[_][]const u8{
            builder.build_root,
            builder.cache_root,
            out,
        }) catch unreachable;

        self.* = .{
            .step = Step.init(.custom, "resources", builder.allocator, make),
            .shader_step = vkgen.ShaderCompileStep.init(builder, &[_][]const u8{ "glslc", "--target-env=vulkan1.2" }, "shaders"),
            .builder = builder,
            .package = .{
                .name = "resources",
                .path = .{ .generated = &self.output_file },
                .dependencies = null,
            },
            .output_file = .{
                .step = &self.step,
                .path = full_out_path,
            },
            .resources = std.ArrayList(u8).init(builder.allocator),
        };

        self.step.dependOn(&self.shader_step.step);
        return self;
    }

    fn renderPath(path: []const u8, writer: anytype) void {
        const separators = &[_]u8{ std.fs.path.sep_windows, std.fs.path.sep_posix };
        var i: usize = 0;
        while (std.mem.indexOfAnyPos(u8, path, i, separators)) |j| {
            writer.writeAll(path[i..j]) catch unreachable;
            switch (std.fs.path.sep) {
                std.fs.path.sep_windows => writer.writeAll("\\\\") catch unreachable,
                std.fs.path.sep_posix => writer.writeByte(std.fs.path.sep_posix) catch unreachable,
                else => unreachable,
            }

            i = j + 1;
        }
        writer.writeAll(path[i..]) catch unreachable;
    }

    pub fn addShader(self: *ResourceGenStep, name: []const u8, source: []const u8) void {
        const shader_out_path = self.shader_step.add(source);
        var writer = self.resources.writer();

        writer.print("pub const {s} = @embedFile(\"", .{name}) catch unreachable;
        renderPath(shader_out_path, writer);
        writer.writeAll("\");\n") catch unreachable;
    }

    fn make(step: *Step) !void {
        const self = @fieldParentPtr(ResourceGenStep, "step", step);
        const cwd = std.fs.cwd();

        const dir = std.fs.path.dirname(self.output_file.path.?).?;
        try cwd.makePath(dir);
        try cwd.writeFile(self.output_file.path.?, self.resources.items);
    }
};

pub fn runBenchmarks(b: *std.build.Builder) void {
    const run_step = b.step("bench-all", "Run all benchmarks without building.");

    const cmd1 = b.addSystemCommand(&.{"zig-out/bin/bevy_benchmarks.exe"});
    run_step.dependOn(&cmd1.step);

    const cmd3 = b.addSystemCommand(&.{"zig-out/bin/bench-zentt.exe"});
    run_step.dependOn(&cmd3.step);

    const cmd2 = b.addSystemCommand(&.{"zig-out/bin/bench-entt.exe"});
    run_step.dependOn(&cmd2.step);
}

pub fn buildBenchmarksBevy(b: *std.build.Builder) void {
    const build_cmd = b.addSystemCommand(&.{ "cargo", "build", "--release", "--manifest-path", "benchmarks/bevy/Cargo.toml", "-Z", "unstable-options", "--out-dir", b.getInstallPath(.bin, "") });
    const run_cmd = b.addSystemCommand(&.{"zig-out/bin/bevy_benchmarks.exe"});

    build_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&build_cmd.step);

    const run_step = b.step("bench-bevy", "Run bevy benchmarks");
    run_step.dependOn(&run_cmd.step);
}

pub fn buildBenchmarksEntt(b: *std.build.Builder, target: std.zig.CrossTarget) void {
    const exe = b.addExecutable("bench-entt", null);
    exe.setTarget(target);
    exe.setBuildMode(.ReleaseFast);
    exe.addIncludeDir("benchmarks/entt/entt/src");
    exe.addCSourceFile("benchmarks/entt/bench.cpp", &.{ "-std=c++17", "-O3" });
    exe.linkLibC();
    exe.linkLibCpp();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("bench-entt", "Run entt benchmarks");
    run_step.dependOn(&run_cmd.step);
}

pub fn buildBenchmarksZentt(b: *std.build.Builder, target: std.zig.CrossTarget) void {
    const exe = b.addExecutable("bench-zentt", "src/benchmark.zig");
    exe.setTarget(target);
    exe.setBuildMode(.ReleaseFast);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("bench-zentt", "Run zentt benchmarks");
    run_step.dependOn(&run_cmd.step);
}

pub fn buildBenchmarks(b: *std.build.Builder, target: std.zig.CrossTarget) void {
    buildBenchmarksBevy(b);
    buildBenchmarksEntt(b, target);
    buildBenchmarksZentt(b, target);
}

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    buildBenchmarks(b, target);
    runBenchmarks(b);

    // generator for zig vulkan bindings.
    const generator_exe = b.addExecutable("vulkan-zig-generator", "generator/main.zig");
    generator_exe.setTarget(target);
    generator_exe.setBuildMode(mode);
    generator_exe.install();

    const vulkan_validation = b.option(bool, "vulkan-validation", "Enable the validation layer in Vulkan") orelse false;

    const zentt_name = if (mode == .Debug) "zentt-debug" else "zentt";
    const exe = b.addExecutable(zentt_name, "src/main.zig");
    const options = b.addOptions();
    options.addOption(std.Target.Os.Tag, "os", target.getOsTag());
    options.addOption(bool, "vulkan_validation", vulkan_validation);
    exe.addOptions("build_options", options);

    // vulkan
    exe.addSystemIncludeDir("D:\\VulkanSDK\\1.2.170.0\\Include");

    // sdl2
    if (target.isWindows()) {
        exe.addLibPath("D:\\dev\\libs\\SDL2-2.0.16\\lib\\x64");
        exe.addSystemIncludeDir("D:\\dev\\libs\\SDL2-2.0.16\\include");
        exe.linkSystemLibrary("imm32");
    }
    exe.linkSystemLibrary("SDL2");

    // imgui
    exe.addIncludeDir("libs/cimgui");
    exe.addIncludeDir("libs/cimgui/imgui");

    const imguiFlags: []const []const u8 = if (mode == .Debug) &.{
        "-Wall",
        "-fno-exceptions",
        "-fno-rtti",
        "-g",
        "-fno-threadsafe-statics",
        "-DIMGUI_IMPL_VULKAN_NO_PROTOTYPES",
        "-DIMGUI_IMPL_API=extern\"C\"",
    } else &.{
        "-Wall",
        "-fno-exceptions",
        "-fno-rtti",
        "-O3",
        "-fno-threadsafe-statics",
        "-DIMGUI_IMPL_VULKAN_NO_PROTOTYPES",
        "-DIMGUI_IMPL_API=extern\"C\"",
    };
    exe.addCSourceFiles(
        &.{
            "libs/cimgui/cimgui.cpp",
            "libs/cimgui/imgui/imgui.cpp",
            "libs/cimgui/imgui/imgui_demo.cpp",
            "libs/cimgui/imgui/imgui_draw.cpp",
            "libs/cimgui/imgui/imgui_tables.cpp",
            "libs/cimgui/imgui/imgui_widgets.cpp",
            "libs/cimgui/imgui/backends/imgui_impl_sdl.cpp",
            "libs/cimgui/imgui/backends/imgui_impl_vulkan.cpp",
        },
        imguiFlags,
    );

    // stb
    exe.addIncludeDir("libs/stb");
    exe.addCSourceFiles(
        &.{"libs/stb/stb_image.c"},
        &.{},
    );

    // ImGuizmo
    exe.addIncludeDir("libs/");
    exe.addCSourceFiles(
        &.{"libs/imguizmo/ImGuizmo.cpp"},
        &.{},
    );

    exe.linkLibC();
    exe.linkLibCpp();
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const vk_xml_path = b.option([]const u8, "vulkan-registry", "Override the path to the Vulkan registry") orelse "src/rendering/vulkan/vk.xml";

    const gen = vkgen.VkGenerateStep.init(b, vk_xml_path, "vk.zig");
    exe.addPackage(gen.package);

    const res = ResourceGenStep.init(b, "resources.zig");
    res.addShader("triangle_vert", "src/rendering/vulkan/shaders/triangle.vert");
    res.addShader("triangle_frag", "src/rendering/vulkan/shaders/triangle.frag");
    exe.addPackage(res.package);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
