const std = @import("std");
const vk = @import("vulkan");
const c = @import("vulkan/c.zig");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const sdl = @import("sdl.zig");

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const Allocator = std.mem.Allocator;
const resources = @import("resources");

const app_name = "vulkan-zig triangle example";

const Vertex = struct {
    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
};

const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
};

pub fn check_vk_result(err: vk.Result) callconv(vk.vulkan_call_conv) void {
    if (err != .success) {
        std.log.err("check_vk_result: {}", .{err});
    }
}
export fn vulkan_loader(function_name: [*:0]const u8, user_data: ?*anyopaque) vk.PfnVoidFunction {
    const instance = @ptrCast(*vk.Instance, @alignCast(@alignOf(vk.Instance), user_data orelse unreachable)).*;
    return sdl.SDL_Vulkan_GetVkGetInstanceProcAddrZig()(instance, function_name);
}

const Details = @import("details_window.zig");

const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;
const Tag = @import("tag_component.zig").Tag;
const Commands = @import("commands.zig");

pub const Position = struct {
    position: [3]f32,
};
pub const Gravity = struct { uiae: f32 = 99 };
pub const A = struct { i: i64 };
pub const B = struct { b: bool, Gravity: Gravity = .{} };
pub const C = struct { i: i16 = 123, b: bool = true, u: u8 = 9 };
pub const D = struct {};

pub fn testSystem1(query: Query(.{ Tag, A })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem2(query: Query(.{ Tag, A, B })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem3(query: Query(.{ Tag, A, B, C })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem4(query: Query(.{ Tag, A, B, C, D })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem5(time: *const Time, query: Query(.{ Tag, B })) !void {
    _ = time;
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

const Time = struct {
    delta: f64 = 0,
    now: f64 = 0,
};

pub fn main() !void {
    // init SDL
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    var extent = vk.Extent2D{ .width = 800, .height = 600 };

    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_FLAGS, 0);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DOUBLEBUFFER, 1);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DEPTH_SIZE, 24);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_STENCIL_SIZE, 8);

    // Create our window
    const window = sdl.SDL_CreateWindow(
        "My Game Window",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        @intCast(c_int, extent.width),
        @intCast(c_int, extent.height),
        sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_SHOWN | sdl.SDL_WINDOW_RESIZABLE,
    ) orelse {
        sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const gc = try GraphicsContext.init(allocator, app_name, window);
    defer gc.deinit();

    std.debug.print("Using device: {s}\n", .{gc.deviceName()});

    var swapchain = try Swapchain.init(&gc, allocator, extent);
    defer swapchain.deinit();

    const push_constants = [_]vk.PushConstantRange{
        .{
            .stage_flags = .{ .vertex_bit = true },
            .offset = 0,
            .size = @sizeOf(f32) * 4,
        },
    };
    const pipeline_layout = try gc.vkd.createPipelineLayout(gc.dev, &.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, &push_constants),
    }, null);
    defer gc.vkd.destroyPipelineLayout(gc.dev, pipeline_layout, null);

    const render_pass = try createRenderPass(&gc, swapchain);
    defer gc.vkd.destroyRenderPass(gc.dev, render_pass, null);

    var pipeline = try createPipeline(&gc, pipeline_layout, render_pass);
    defer gc.vkd.destroyPipeline(gc.dev, pipeline, null);

    var framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain);
    defer destroyFramebuffers(&gc, allocator, framebuffers);

    const pool = try gc.vkd.createCommandPool(gc.dev, &.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = gc.graphics_queue.family,
    }, null);
    defer gc.vkd.destroyCommandPool(gc.dev, pool, null);

    const buffer = try gc.vkd.createBuffer(gc.dev, &.{
        .flags = .{},
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
    }, null);
    defer gc.vkd.destroyBuffer(gc.dev, buffer, null);
    const mem_reqs = gc.vkd.getBufferMemoryRequirements(gc.dev, buffer);
    const memory = try gc.allocate(mem_reqs, .{ .device_local_bit = true });
    defer gc.vkd.freeMemory(gc.dev, memory, null);
    try gc.vkd.bindBufferMemory(gc.dev, buffer, memory, 0);

    try uploadVertices(&gc, pool, buffer);

    var cmdbufs = try createCommandBuffers(
        &gc,
        pool,
        allocator,
        buffer,
        swapchain.extent,
        render_pass,
        pipeline,
        framebuffers,
    );
    defer destroyCommandBuffers(&gc, pool, allocator, cmdbufs);

    var imgui_cmdbufs = try createCommandBuffers(
        &gc,
        pool,
        allocator,
        buffer,
        swapchain.extent,
        render_pass,
        pipeline,
        framebuffers,
    );
    defer destroyCommandBuffers(&gc, pool, allocator, imgui_cmdbufs);

    // Create Descriptor Pool

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
    const descriptor_pool = try gc.vkd.createDescriptorPool(gc.dev, &pool_info, null);
    defer gc.vkd.destroyDescriptorPool(gc.dev, descriptor_pool, null);

    // init imgui
    _ = imgui.CreateContext();
    var io = imgui.GetIO();
    io.ConfigFlags = io.ConfigFlags.with(.{ .DockingEnable = true, .ViewportsEnable = true });
    _ = imgui2.ImGui_ImplSDL2_InitForVulkan(window);
    defer imgui2.ImGui_ImplSDL2_Shutdown();

    {
        var instance = gc.instance;
        if (!imgui2.ImGui_ImplVulkan_LoadFunctions(vulkan_loader, &instance)) {
            return error.ImguiFailedToLoadVulkanFunctions;
        }
    }

    const info = imgui2.ImGui_ImplVulkan_InitInfo{
        .Instance = gc.instance,
        .PhysicalDevice = gc.pdev,
        .Device = gc.dev,
        .QueueFamily = gc.graphics_queue.family,
        .Queue = gc.graphics_queue.handle,
        .PipelineCache = null,
        .DescriptorPool = descriptor_pool,
        .Subpass = 0,
        .MinImageCount = @intCast(u32, swapchain.swap_images.len),
        .ImageCount = @intCast(u32, swapchain.swap_images.len),
        .MSAASamples = (vk.SampleCountFlags{ .@"1_bit" = true }).toInt(),
        .Allocator = null,
        .CheckVkResultFn = check_vk_result,
    };
    _ = imgui2.ImGui_ImplVulkan_Init(&info, render_pass);
    defer imgui2.ImGui_ImplVulkan_Shutdown();

    // Upload Fonts
    {
        // Use any command queue
        var cmdbuf: vk.CommandBuffer = undefined;

        try gc.vkd.allocateCommandBuffers(gc.dev, &.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast([*]vk.CommandBuffer, &cmdbuf));
        errdefer gc.vkd.freeCommandBuffers(gc.dev, pool, 1, @ptrCast([*]const vk.CommandBuffer, &cmdbuf));

        try gc.vkd.beginCommandBuffer(cmdbuf, &.{
            .flags = .{ .one_time_submit_bit = true },
            .p_inheritance_info = null,
        });

        if (!imgui2.ImGui_ImplVulkan_CreateFontsTexture(cmdbuf)) {
            return error.ImguiFailedToCreateFontsTexture;
        }

        try gc.vkd.endCommandBuffer(cmdbuf);

        const si = vk.SubmitInfo{
            .wait_semaphore_count = 0,
            .p_wait_semaphores = undefined,
            .p_wait_dst_stage_mask = undefined,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &cmdbuf),
            .signal_semaphore_count = 0,
            .p_signal_semaphores = undefined,
        };
        try gc.vkd.queueSubmit(gc.graphics_queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &si), .null_handle);
        try gc.vkd.queueWaitIdle(gc.graphics_queue.handle);

        imgui2.ImGui_ImplVulkan_DestroyFontUploadObjects();
    }

    var world = try World.init(allocator);
    defer world.deinit();
    defer world.dumpGraph() catch {};
    try world.addSystem(testSystem1, "{A}");
    try world.addSystem(testSystem2, "{A, B}");
    try world.addSystem(testSystem3, "{A, B, C}");
    try world.addSystem(testSystem4, "{A, B, C, D}");
    try world.addSystem(testSystem5, "{B}");

    _ = try world.addResource(Time{});
    var commands = try world.addResource(Commands.init(allocator));
    defer commands.deinit();

    const e = try commands.createEntity();
    _ = try commands.addComponent(e, Tag{ .name = "e" });
    _ = try commands.addComponent(e, C{ .i = 69 });
    _ = try commands.addComponent(e, B{ .b = false });
    _ = try commands.addComponent(e, A{ .i = 31 });
    _ = try commands.addComponent(e, D{});
    _ = try commands.applyCommands(world);

    var details = Details.init(allocator);
    var selectedEntity: EntityId = 0;

    var lastFrameTime = std.time.nanoTimestamp();
    var frameTimeSmoothed: f64 = 0;

    var quit = false;
    var i: i64 = 0;
    while (!quit) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            _ = imgui2.ImGui_ImplSDL2_ProcessEvent(event);
            switch (event.@"type") {
                sdl.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }
        const currentFrameTime = std.time.nanoTimestamp();
        const frameTimeNs = currentFrameTime - lastFrameTime;
        const frameTime = (@intToFloat(f64, frameTimeNs) / std.time.ns_per_ms);
        frameTimeSmoothed = (0.9 * frameTimeSmoothed) + (0.1 * frameTime);
        lastFrameTime = currentFrameTime;
        var fps: f64 = blk: {
            if (frameTimeSmoothed == 0) {
                break :blk -1;
            } else {
                break :blk (1000.0 / frameTimeSmoothed);
            }
        };
        _ = fps;

        var timeResource = try world.getResource(Time);
        timeResource.delta = @intToFloat(f64, frameTimeNs) / std.time.ns_per_s;
        timeResource.now += timeResource.delta;

        const cmdbuf = cmdbufs[swapchain.image_index];
        const imgui_cmdbuf = imgui_cmdbufs[swapchain.image_index];
        _ = imgui_cmdbuf;

        var w: c_int = undefined;
        var h: c_int = undefined;
        sdl.SDL_Vulkan_GetDrawableSize(window, &w, &h);

        try swapchain.prepare();

        imgui2.newFrame();
        imgui2.dockspace();

        var b = true;
        imgui2.showDemoWindow(&b);

        if (imgui.Begin("Stats")) {
            imgui.LabelText("Frame time: ", "%.2f", frameTimeSmoothed);
            imgui.LabelText("FPS: ", "%.1f", fps);
        }
        imgui.End();

        if (imgui.Begin("Entities")) {
            if (imgui.Button("Create Entity")) {
                const entt = try commands.createEntity();
                _ = entt;
                // _ = try commands.addComponent(e, Tag{ .name = "e" });
            }

            var tableFlags = imgui.TableFlags{
                .Resizable = true,
                .RowBg = true,
                .Sortable = true,
            };
            tableFlags = tableFlags.with(imgui.TableFlags.Borders);
            if (imgui.BeginTable("Entities", 4, tableFlags, .{}, 0)) {
                defer imgui.EndTable();

                var entityIter = world.entities.iterator();
                while (entityIter.next()) |entry| {
                    const entityId = entry.key_ptr.*;
                    imgui.PushIDInt64(entityId);
                    defer imgui.PopID();

                    imgui.TableNextRow(.{}, 0);
                    _ = imgui.TableSetColumnIndex(0);
                    imgui.Text("%d", entityId);

                    _ = imgui.TableSetColumnIndex(1);
                    if (try world.getComponent(entityId, Tag)) |tag| {
                        imgui.Text("%.*s", tag.name.len, tag.name.ptr);
                    }

                    _ = imgui.TableSetColumnIndex(2);
                    if (imgui.Button("Select")) {
                        // const entt = try commands.getEntity(entityId);
                        // _ = try commands.addComponent(entt, Tag{ .name = "lol" });
                        selectedEntity = entityId;
                    }

                    _ = imgui.TableSetColumnIndex(3);
                    if (imgui.Button("Destroy")) {
                        try commands.destroyEntity(entityId);
                    }
                }
            }
        }
        imgui.End();

        try details.draw(world, selectedEntity, commands);

        try world.runFrameSystems();
        _ = try commands.applyCommands(world);

        imgui2.render();
        imgui2.endFrame();
        try beginRecordCommandBuffer(
            &gc,
            pool,
            buffer,
            swapchain.extent,
            render_pass,
            pipeline,
            framebuffers[swapchain.image_index],
            cmdbuf,
        );
        imgui2.ImGui_ImplVulkan_RenderDrawData(imgui2.getDrawData(), cmdbuf, .null_handle);
        try endRecordCommandBuffer(&gc, cmdbuf);

        const state = swapchain.present(cmdbuf) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        imgui2.updatePlatformWindows();

        if (state == .suboptimal or extent.width != @intCast(u32, w) or extent.height != @intCast(u32, h)) {
            extent.width = @intCast(u32, w);
            extent.height = @intCast(u32, h);
            try swapchain.recreate(extent);

            destroyFramebuffers(&gc, allocator, framebuffers);
            framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain);

            destroyCommandBuffers(&gc, pool, allocator, cmdbufs);
            cmdbufs = try createCommandBuffers(
                &gc,
                pool,
                allocator,
                buffer,
                swapchain.extent,
                render_pass,
                pipeline,
                framebuffers,
            );
        }

        i += 1;
        // if (i >= 5) break;
    }

    try swapchain.waitForAllFences();
}

fn uploadVertices(gc: *const GraphicsContext, pool: vk.CommandPool, buffer: vk.Buffer) !void {
    const staging_buffer = try gc.vkd.createBuffer(gc.dev, &.{
        .flags = .{},
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
    }, null);
    defer gc.vkd.destroyBuffer(gc.dev, staging_buffer, null);
    const mem_reqs = gc.vkd.getBufferMemoryRequirements(gc.dev, staging_buffer);
    const staging_memory = try gc.allocate(mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer gc.vkd.freeMemory(gc.dev, staging_memory, null);
    try gc.vkd.bindBufferMemory(gc.dev, staging_buffer, staging_memory, 0);

    {
        const data = try gc.vkd.mapMemory(gc.dev, staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer gc.vkd.unmapMemory(gc.dev, staging_memory);

        const gpu_vertices = @ptrCast([*]Vertex, @alignCast(@alignOf(Vertex), data));
        for (vertices) |vertex, i| {
            gpu_vertices[i] = vertex;
        }
    }

    try copyBuffer(gc, pool, buffer, staging_buffer, @sizeOf(@TypeOf(vertices)));
}

fn copyBuffer(gc: *const GraphicsContext, pool: vk.CommandPool, dst: vk.Buffer, src: vk.Buffer, size: vk.DeviceSize) !void {
    var cmdbuf: vk.CommandBuffer = undefined;
    try gc.vkd.allocateCommandBuffers(gc.dev, &.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast([*]vk.CommandBuffer, &cmdbuf));
    defer gc.vkd.freeCommandBuffers(gc.dev, pool, 1, @ptrCast([*]const vk.CommandBuffer, &cmdbuf));

    try gc.vkd.beginCommandBuffer(cmdbuf, &.{
        .flags = .{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    });

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    gc.vkd.cmdCopyBuffer(cmdbuf, src, dst, 1, @ptrCast([*]const vk.BufferCopy, &region));

    try gc.vkd.endCommandBuffer(cmdbuf);

    const si = vk.SubmitInfo{
        .wait_semaphore_count = 0,
        .p_wait_semaphores = undefined,
        .p_wait_dst_stage_mask = undefined,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &cmdbuf),
        .signal_semaphore_count = 0,
        .p_signal_semaphores = undefined,
    };
    try gc.vkd.queueSubmit(gc.graphics_queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &si), .null_handle);
    try gc.vkd.queueWaitIdle(gc.graphics_queue.handle);
}

fn createCommandBuffers(
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
    allocator: Allocator,
    buffer: vk.Buffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    framebuffers: []vk.Framebuffer,
) ![]vk.CommandBuffer {
    const cmdbufs = try allocator.alloc(vk.CommandBuffer, framebuffers.len);
    errdefer allocator.free(cmdbufs);

    _ = pipeline;
    _ = render_pass;
    _ = extent;
    _ = buffer;
    _ = pool;
    _ = gc;

    try gc.vkd.allocateCommandBuffers(gc.dev, &.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = @truncate(u32, cmdbufs.len),
    }, cmdbufs.ptr);
    errdefer gc.vkd.freeCommandBuffers(gc.dev, pool, @truncate(u32, cmdbufs.len), cmdbufs.ptr);

    return cmdbufs;
}

fn beginRecordCommandBuffer(
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
    buffer: vk.Buffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    framebuffer: vk.Framebuffer,
    cmdbuf: vk.CommandBuffer,
) !void {
    _ = pool;
    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
    };

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @intToFloat(f32, extent.width),
        .height = @intToFloat(f32, extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    try gc.vkd.beginCommandBuffer(cmdbuf, &.{
        .flags = .{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    });

    gc.vkd.cmdSetViewport(cmdbuf, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));
    gc.vkd.cmdSetScissor(cmdbuf, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));

    // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    gc.vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = render_pass,
        .framebuffer = framebuffer,
        .render_area = render_area,
        .clear_value_count = 1,
        .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear),
    }, .@"inline");

    _ = pipeline;
    _ = buffer;
    gc.vkd.cmdBindPipeline(cmdbuf, .graphics, pipeline);
    const offset = [_]vk.DeviceSize{0};
    gc.vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast([*]const vk.Buffer, &buffer), &offset);
    gc.vkd.cmdDraw(cmdbuf, vertices.len, 1, 0, 0);
}

fn endRecordCommandBuffer(gc: *const GraphicsContext, cmdbuf: vk.CommandBuffer) !void {
    gc.vkd.cmdEndRenderPass(cmdbuf);
    try gc.vkd.endCommandBuffer(cmdbuf);
}

fn destroyCommandBuffers(gc: *const GraphicsContext, pool: vk.CommandPool, allocator: Allocator, cmdbufs: []vk.CommandBuffer) void {
    gc.vkd.freeCommandBuffers(gc.dev, pool, @truncate(u32, cmdbufs.len), cmdbufs.ptr);
    allocator.free(cmdbufs);
}

fn createFramebuffers(gc: *const GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.vkd.destroyFramebuffer(gc.dev, fb, null);

    for (framebuffers) |*fb| {
        fb.* = try gc.vkd.createFramebuffer(gc.dev, &.{
            .flags = .{},
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast([*]const vk.ImageView, &swapchain.swap_images[i].view),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroyFramebuffers(gc: *const GraphicsContext, allocator: Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| gc.vkd.destroyFramebuffer(gc.dev, fb, null);
    allocator.free(framebuffers);
}

fn createRenderPass(gc: *const GraphicsContext, swapchain: Swapchain) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .flags = .{},
        .format = swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .dont_care,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .@"undefined",
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .flags = .{},
        .pipeline_bind_point = .graphics,
        .input_attachment_count = 0,
        .p_input_attachments = undefined,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast([*]const vk.AttachmentReference, &color_attachment_ref),
        .p_resolve_attachments = null,
        .p_depth_stencil_attachment = null,
        .preserve_attachment_count = 0,
        .p_preserve_attachments = undefined,
    };

    const dependency = vk.SubpassDependency{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true },
        .dst_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true },
        .src_access_mask = vk.AccessFlags{},
        .dst_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true },
        .dependency_flags = vk.DependencyFlags{},
    };

    return try gc.vkd.createRenderPass(gc.dev, &.{
        .flags = .{},
        .attachment_count = 1,
        .p_attachments = @ptrCast([*]const vk.AttachmentDescription, &color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast([*]const vk.SubpassDescription, &subpass),
        .dependency_count = 1,
        .p_dependencies = @ptrCast([*]const vk.SubpassDependency, &dependency),
    }, null);
}

fn createPipeline(
    gc: *const GraphicsContext,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
) !vk.Pipeline {
    const vert = try gc.vkd.createShaderModule(gc.dev, &.{
        .flags = .{},
        .code_size = resources.triangle_vert.len,
        .p_code = @ptrCast([*]const u32, resources.triangle_vert),
    }, null);
    defer gc.vkd.destroyShaderModule(gc.dev, vert, null);

    const frag = try gc.vkd.createShaderModule(gc.dev, &.{
        .flags = .{},
        .code_size = resources.triangle_frag.len,
        .p_code = @ptrCast([*]const u32, resources.triangle_frag),
    }, null);
    defer gc.vkd.destroyShaderModule(gc.dev, frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .flags = .{},
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
            .p_specialization_info = null,
        },
        .{
            .flags = .{},
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
            .p_specialization_info = null,
        },
    };

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .flags = .{},
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast([*]const vk.VertexInputBindingDescription, &Vertex.binding_description),
        .vertex_attribute_description_count = Vertex.attribute_description.len,
        .p_vertex_attribute_descriptions = &Vertex.attribute_description,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .flags = .{},
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .flags = .{},
        .viewport_count = 1,
        .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .flags = .{},
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .flags = .{},
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.FALSE,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .flags = .{},
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast([*]const vk.PipelineColorBlendAttachmentState, &pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.vkd.createGraphicsPipelines(
        gc.dev,
        .null_handle,
        1,
        @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &gpci),
        null,
        @ptrCast([*]vk.Pipeline, &pipeline),
    );
    return pipeline;
}
