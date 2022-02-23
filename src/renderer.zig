const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const sdl = @import("sdl.zig");

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const resources = @import("resources");

const Self = @This();
const Renderer = @This();

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

allocator: Allocator,
gc: GraphicsContext,

// Things that need to be recreated when the window resizes
swapchain: Swapchain,
renderPass: vk.RenderPass,
pipelineLayout: vk.PipelineLayout,
pipeline: vk.Pipeline,
framebuffers: []vk.Framebuffer,
commandPool: vk.CommandPool,
triangleBuffer: vk.Buffer,
triangleMemory: vk.DeviceMemory,
commandBuffers: []vk.CommandBuffer,

pub fn init(allocator: Allocator, window: *sdl.SDL_Window, extent: vk.Extent2D) !*Self {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;

    self.gc = try GraphicsContext.init(allocator, "App", window);
    errdefer self.gc.deinit();

    std.debug.print("Using device: {s}\n", .{self.gc.deviceName()});

    self.swapchain = try Swapchain.init(&self.gc, allocator, extent);
    errdefer self.swapchain.deinit();

    const push_constants = [_]vk.PushConstantRange{
        .{
            .stage_flags = .{ .vertex_bit = true },
            .offset = 0,
            .size = @sizeOf(f32) * 4,
        },
    };
    self.pipelineLayout = try self.gc.vkd.createPipelineLayout(self.gc.dev, &.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, &push_constants),
    }, null);
    errdefer self.gc.vkd.destroyPipelineLayout(self.gc.dev, self.pipelineLayout, null);

    self.renderPass = try createRenderPass(&self.gc, self.swapchain);
    errdefer self.gc.vkd.destroyRenderPass(self.gc.dev, self.renderPass, null);

    self.pipeline = try createPipeline(&self.gc, self.pipelineLayout, self.renderPass);
    errdefer self.gc.vkd.destroyPipeline(self.gc.dev, self.pipeline, null);

    self.framebuffers = try createFramebuffers(&self.gc, allocator, self.renderPass, self.swapchain);
    errdefer destroyFramebuffers(&self.gc, allocator, self.framebuffers);

    self.commandPool = try self.gc.vkd.createCommandPool(self.gc.dev, &.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = self.gc.graphics_queue.family,
    }, null);
    errdefer self.gc.vkd.destroyCommandPool(self.gc.dev, self.commandPool, null);

    self.triangleBuffer = try self.gc.vkd.createBuffer(self.gc.dev, &.{
        .flags = .{},
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
    }, null);
    errdefer self.gc.vkd.destroyBuffer(self.gc.dev, self.triangleBuffer, null);
    const mem_reqs = self.gc.vkd.getBufferMemoryRequirements(self.gc.dev, self.triangleBuffer);
    self.triangleMemory = try self.gc.allocate(mem_reqs, .{ .device_local_bit = true });
    errdefer self.gc.vkd.freeMemory(self.gc.dev, self.triangleMemory, null);
    try self.gc.vkd.bindBufferMemory(self.gc.dev, self.triangleBuffer, self.triangleMemory, 0);

    try uploadVertices(&self.gc, self.commandPool, self.triangleBuffer);

    self.commandBuffers = try createCommandBuffers(
        &self.gc,
        self.commandPool,
        allocator,
        self.framebuffers,
    );
    errdefer destroyCommandBuffers(&self.gc, self.commandPool, allocator, self.commandBuffers);

    return self;
}

pub fn waitIdle(self: *const Self) void {
    self.swapchain.waitForAllFences() catch |err| {
        std.log.err("Failed to wait for all fences on the swapchain: {}", .{err});
    };
}

pub fn deinit(self: *Self) void {
    destroyCommandBuffers(&self.gc, self.commandPool, self.allocator, self.commandBuffers);
    self.gc.vkd.destroyBuffer(self.gc.dev, self.triangleBuffer, null);
    self.gc.vkd.freeMemory(self.gc.dev, self.triangleMemory, null);
    self.gc.vkd.destroyCommandPool(self.gc.dev, self.commandPool, null);
    destroyFramebuffers(&self.gc, self.allocator, self.framebuffers);
    self.gc.vkd.destroyPipeline(self.gc.dev, self.pipeline, null);
    self.gc.vkd.destroyPipelineLayout(self.gc.dev, self.pipelineLayout, null);
    self.gc.vkd.destroyRenderPass(self.gc.dev, self.renderPass, null);
    self.swapchain.deinit();
    self.gc.deinit();

    self.allocator.destroy(self);
}

pub fn getCommandBuffer(self: *const Self) vk.CommandBuffer {
    return self.commandBuffers[self.swapchain.image_index];
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
    framebuffers: []vk.Framebuffer,
) ![]vk.CommandBuffer {
    const commandBuffers = try allocator.alloc(vk.CommandBuffer, framebuffers.len);
    errdefer allocator.free(commandBuffers);

    try gc.vkd.allocateCommandBuffers(gc.dev, &.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = @truncate(u32, commandBuffers.len),
    }, commandBuffers.ptr);
    errdefer gc.vkd.freeCommandBuffers(gc.dev, pool, @truncate(u32, commandBuffers.len), commandBuffers.ptr);

    return commandBuffers;
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

fn destroyCommandBuffers(gc: *const GraphicsContext, pool: vk.CommandPool, allocator: Allocator, commandBuffers: []vk.CommandBuffer) void {
    gc.vkd.freeCommandBuffers(gc.dev, pool, @truncate(u32, commandBuffers.len), commandBuffers.ptr);
    allocator.free(commandBuffers);
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

pub fn beginRender(self: *Self) !void {
    try beginRecordCommandBuffer(
        &self.gc,
        self.commandPool,
        self.triangleBuffer,
        self.swapchain.extent,
        self.renderPass,
        self.pipeline,
        self.framebuffers[self.swapchain.image_index],
        self.getCommandBuffer(),
    );
}

pub fn endRender(self: *Self, newExtent: vk.Extent2D) !void {
    const cmdbuf = self.commandBuffers[self.swapchain.image_index];
    try endRecordCommandBuffer(&self.gc, cmdbuf);

    const state = self.swapchain.present(cmdbuf) catch |err| switch (err) {
        error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
        else => |narrow| return narrow,
    };

    if (state == .suboptimal or self.swapchain.extent.width != @intCast(u32, newExtent.width) or self.swapchain.extent.height != @intCast(u32, newExtent.height)) {
        try self.swapchain.recreate(newExtent);

        destroyFramebuffers(&self.gc, self.allocator, self.framebuffers);
        self.framebuffers = try createFramebuffers(&self.gc, self.allocator, self.renderPass, self.swapchain);

        destroyCommandBuffers(&self.gc, self.commandPool, self.allocator, self.commandBuffers);
        self.commandBuffers = try createCommandBuffers(
            &self.gc,
            self.commandPool,
            self.allocator,
            self.framebuffers,
        );
    }
}
