const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const sdl = @import("sdl.zig");

const imgui2 = @import("imgui2.zig");

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

const Image = struct {
    image: vk.Image,
    imageView: vk.ImageView,
    memory: vk.DeviceMemory,
};

allocator: Allocator,
gc: GraphicsContext,

descriptorPool: vk.DescriptorPool,

// Things that need to be recreated when the window resizes
swapchain: Swapchain,
framebuffers: []vk.Framebuffer,
commandBuffers: []vk.CommandBuffer,

sceneRenderPass: vk.RenderPass,
sceneImages: []Image,
sceneFrameBuffers: []vk.Framebuffer,
sceneDescriptorSetLayout: vk.DescriptorSetLayout,
sceneDescriptorSets: []vk.DescriptorSet,
sceneImageSampler: vk.Sampler,

mainRenderPass: vk.RenderPass,

commandPool: vk.CommandPool,
pipelineLayout: vk.PipelineLayout,
pipeline: vk.Pipeline,

triangleBuffer: vk.Buffer,
triangleMemory: vk.DeviceMemory,

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

    // main render pass
    self.mainRenderPass = try createRenderPass(&self.gc, self.swapchain.surface_format.format, .present_src_khr);
    errdefer self.gc.vkd.destroyRenderPass(self.gc.dev, self.mainRenderPass, null);

    self.framebuffers = try createFramebuffers(&self.gc, allocator, self.mainRenderPass, self.swapchain);
    errdefer destroyFramebuffers(&self.gc, allocator, self.framebuffers);

    // scene render pass
    const sceneExtent = vk.Extent2D{ .width = 1920, .height = 1080 };
    self.sceneRenderPass = try createSceneRenderPass(&self.gc, self.swapchain.surface_format.format, .shader_read_only_optimal);
    errdefer self.gc.vkd.destroyRenderPass(self.gc.dev, self.sceneRenderPass, null);

    self.sceneImages = try createSceneImage(&self.gc, allocator, self.swapchain.swap_images.len, self.swapchain.surface_format.format, sceneExtent);
    errdefer destroySceneImages(&self.gc, allocator, self.sceneImages);

    self.sceneFrameBuffers = try createSceneFrameBuffers(&self.gc, allocator, self.sceneRenderPass, self.sceneImages, sceneExtent);
    errdefer destroySceneFramebuffers(&self.gc, allocator, self.sceneFrameBuffers);

    self.descriptorPool = try createDescriptorPool(&self.gc);
    errdefer self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.descriptorPool, null);

    self.sceneImageSampler = try createSceneImageSampler(&self.gc);
    errdefer self.gc.vkd.destroySampler(self.gc.dev, self.sceneImageSampler, null);

    self.sceneDescriptorSetLayout = try createSceneDescriptorSetLayout(&self.gc);
    errdefer self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, self.sceneDescriptorSetLayout, null);

    self.sceneDescriptorSets = try createSceneDescriptorSets(&self.gc, allocator, self.sceneImages, self.descriptorPool, self.sceneDescriptorSetLayout, self.sceneImageSampler);
    errdefer allocator.free(self.sceneDescriptorSets);

    // other stuff

    self.pipeline = try createPipeline(&self.gc, self.pipelineLayout, self.mainRenderPass);
    errdefer self.gc.vkd.destroyPipeline(self.gc.dev, self.pipeline, null);
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

    self.allocator.free(self.sceneDescriptorSets);

    self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.descriptorPool, null);
    self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, self.sceneDescriptorSetLayout, null);
    self.gc.vkd.destroySampler(self.gc.dev, self.sceneImageSampler, null);

    // scene
    destroySceneFramebuffers(&self.gc, self.allocator, self.sceneFrameBuffers);
    destroySceneImages(&self.gc, self.allocator, self.sceneImages);

    // main
    destroyFramebuffers(&self.gc, self.allocator, self.framebuffers);
    self.gc.vkd.destroyPipeline(self.gc.dev, self.pipeline, null);
    self.gc.vkd.destroyPipelineLayout(self.gc.dev, self.pipelineLayout, null);
    self.gc.vkd.destroyRenderPass(self.gc.dev, self.mainRenderPass, null);
    self.gc.vkd.destroyRenderPass(self.gc.dev, self.sceneRenderPass, null);
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
    cmdbuf: vk.CommandBuffer,
) !void {
    try gc.vkd.beginCommandBuffer(cmdbuf, &.{
        .flags = .{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    });
}

fn drawTriangle(
    gc: *const GraphicsContext,
    buffer: vk.Buffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    framebuffer: vk.Framebuffer,
    cmdbuf: vk.CommandBuffer,
) void {
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

    gc.vkd.cmdSetViewport(cmdbuf, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));
    gc.vkd.cmdSetScissor(cmdbuf, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));

    // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };
    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 1, 0, 1, 1 } },
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
    gc.vkd.cmdEndRenderPass(cmdbuf);
}

fn prepareImgui(
    gc: *const GraphicsContext,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    framebuffer: vk.Framebuffer,
    cmdbuf: vk.CommandBuffer,
) void {
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

    gc.vkd.cmdSetViewport(cmdbuf, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));
    gc.vkd.cmdSetScissor(cmdbuf, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));

    // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
    };

    gc.vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = render_pass,
        .framebuffer = framebuffer,
        .render_area = render_area,
        .clear_value_count = 1,
        .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear),
    }, .@"inline");
}

fn endRecordCommandBuffer(gc: *const GraphicsContext, cmdbuf: vk.CommandBuffer) !void {
    gc.vkd.cmdEndRenderPass(cmdbuf);
    try gc.vkd.endCommandBuffer(cmdbuf);
}

fn destroyCommandBuffers(gc: *const GraphicsContext, pool: vk.CommandPool, allocator: Allocator, commandBuffers: []vk.CommandBuffer) void {
    gc.vkd.freeCommandBuffers(gc.dev, pool, @truncate(u32, commandBuffers.len), commandBuffers.ptr);
    allocator.free(commandBuffers);
}

fn createSceneImage(gc: *const GraphicsContext, allocator: Allocator, amount: usize, format: vk.Format, extent: vk.Extent2D) ![]Image {
    const images = try allocator.alloc(Image, amount);
    errdefer allocator.free(images);

    var i: usize = 0;
    errdefer for (images[0..i]) |img| {
        gc.vkd.destroyImageView(gc.dev, img.imageView, null);
        gc.vkd.destroyImage(gc.dev, img.image, null);
        gc.vkd.freeMemory(gc.dev, img.memory, null);
    };

    const queue_family_indices: [1]u32 = .{0};

    for (images) |*iv| {
        // This triggers the following compiler bug: generating const value for struct field 'format'
        // iv.* = try gc.vkd.createImage(gc.dev, &.{
        //     .flags = .{},
        //     .image_type = .@"2d",
        //     .format = format2,
        //     .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
        //     .mip_levels = 1,
        //     .array_layers = 1,
        //     .samples = .{ .@"1_bit" = true },
        //     .tiling = .optimal,
        //     .usage = .{ .sampled_bit = true, .color_attachment_bit = true },
        //     .sharing_mode = .exclusive,
        //     .queue_family_index_count = 0,
        //     .p_queue_family_indices = @ptrCast([*]const u32, &queue_family_indices[0]),
        //     .initial_layout = .@"undefined",
        // }, null);

        var createInfo: vk.ImageCreateInfo = undefined;
        createInfo.s_type = .image_create_info;
        createInfo.p_next = null;
        createInfo.flags = .{};
        createInfo.image_type = .@"2d";
        createInfo.format = format;
        createInfo.extent = .{ .width = extent.width, .height = extent.height, .depth = 1 };
        createInfo.mip_levels = 1;
        createInfo.array_layers = 1;
        createInfo.samples = .{ .@"1_bit" = true };
        createInfo.tiling = .optimal;
        createInfo.usage = .{ .sampled_bit = true, .color_attachment_bit = true };
        createInfo.sharing_mode = .exclusive;
        createInfo.queue_family_index_count = 0;
        createInfo.p_queue_family_indices = @ptrCast([*]const u32, &queue_family_indices[0]);
        createInfo.initial_layout = .@"undefined";

        iv.image = try gc.vkd.createImage(gc.dev, &createInfo, null);
        const memoryRequirements = gc.vkd.getImageMemoryRequirements(gc.dev, iv.image);

        const memoryTypeIndex = try gc.findMemoryTypeIndex(memoryRequirements.memory_type_bits, .{ .device_local_bit = true });
        iv.memory = try gc.vkd.allocateMemory(gc.dev, &.{
            .allocation_size = memoryRequirements.size,
            .memory_type_index = memoryTypeIndex,
        }, null);

        try gc.vkd.bindImageMemory(gc.dev, iv.image, iv.memory, 0);

        iv.imageView = try gc.vkd.createImageView(gc.dev, &.{
            .flags = .{},
            .image = iv.image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);

        i += 1;
    }

    return images;
}

fn destroySceneImages(gc: *const GraphicsContext, allocator: Allocator, images: []const Image) void {
    for (images) |img| {
        gc.vkd.destroyImageView(gc.dev, img.imageView, null);
        gc.vkd.destroyImage(gc.dev, img.image, null);
        gc.vkd.freeMemory(gc.dev, img.memory, null);
    }
    allocator.free(images);
}

fn createSceneFrameBuffers(gc: *const GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, images: []Image, extent: vk.Extent2D) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.vkd.destroyFramebuffer(gc.dev, fb, null);

    for (framebuffers) |*fb| {
        fb.* = try gc.vkd.createFramebuffer(gc.dev, &.{
            .flags = .{},
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast([*]const vk.ImageView, &images[i].imageView),
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroySceneFramebuffers(gc: *const GraphicsContext, allocator: Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| gc.vkd.destroyFramebuffer(gc.dev, fb, null);
    allocator.free(framebuffers);
}

fn createDescriptorPool(gc: *const GraphicsContext) !vk.DescriptorPool {
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
    return try gc.vkd.createDescriptorPool(gc.dev, &pool_info, null);
}

fn createSceneDescriptorSetLayout(gc: *const GraphicsContext) !vk.DescriptorSetLayout {
    const binding = vk.DescriptorSetLayoutBinding{
        .binding = 0,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .stage_flags = .{ .fragment_bit = true },
        .p_immutable_samplers = null,
    };

    return try gc.vkd.createDescriptorSetLayout(gc.dev, &.{
        .flags = .{},
        .binding_count = 1,
        .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, &binding),
    }, null);
}

fn createSceneImageSampler(gc: *const GraphicsContext) !vk.Sampler {
    return try gc.vkd.createSampler(gc.dev, &.{
        .flags = .{},
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .mip_lod_bias = 0,
        .anisotropy_enable = 0,
        .max_anisotropy = 1,
        .compare_enable = 0,
        .compare_op = .never,
        .min_lod = -1000,
        .max_lod = 1000,
        .border_color = .float_transparent_black,
        .unnormalized_coordinates = 0,
    }, null);
}

fn createSceneDescriptorSets(gc: *const GraphicsContext, allocator: Allocator, images: []Image, descriptorPool: vk.DescriptorPool, descriptorSetLayout: vk.DescriptorSetLayout, sampler: vk.Sampler) ![]vk.DescriptorSet {
    const descriptorSets = try allocator.alloc(vk.DescriptorSet, images.len);
    errdefer allocator.free(descriptorSets);

    for (images) |*image, i| {
        try gc.vkd.allocateDescriptorSets(gc.dev, &.{
            .descriptor_pool = descriptorPool,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &descriptorSetLayout),
        }, @ptrCast([*]vk.DescriptorSet, &descriptorSets[i]));

        const desc_image = vk.DescriptorImageInfo{
            .sampler = sampler,
            .image_view = image.imageView,
            .image_layout = .shader_read_only_optimal,
        };

        // const buffer_info: vk.DescriptorBufferInfo = undefined;

        var write_desc: vk.WriteDescriptorSet = undefined;
        std.mem.set(u8, std.mem.asBytes(&write_desc), 0);
        write_desc.s_type = .write_descriptor_set;
        write_desc.dst_set = descriptorSets[i];
        write_desc.dst_binding = 0;
        write_desc.dst_array_element = 0;
        write_desc.descriptor_count = 1;
        write_desc.descriptor_type = .combined_image_sampler;
        write_desc.p_image_info = @ptrCast([*]const vk.DescriptorImageInfo, &desc_image);

        gc.vkd.updateDescriptorSets(gc.dev, 1, @ptrCast([*]const vk.WriteDescriptorSet, &write_desc), 0, @ptrCast([*]const vk.CopyDescriptorSet, &std.mem.zeroes(vk.CopyDescriptorSet)));
    }

    return descriptorSets;
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

fn createSceneRenderPass(gc: *const GraphicsContext, format: vk.Format, finalImageLayout: vk.ImageLayout) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .flags = .{},
        .format = format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .@"undefined",
        .final_layout = finalImageLayout,
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
        .src_stage_mask = vk.PipelineStageFlags{ .fragment_shader_bit = true },
        .dst_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true },
        .src_access_mask = vk.AccessFlags{ .shader_read_bit = true },
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

fn createRenderPass(gc: *const GraphicsContext, format: vk.Format, finalImageLayout: vk.ImageLayout) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .flags = .{},
        .format = format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .@"undefined",
        .final_layout = finalImageLayout,
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

pub fn getSceneImageDescriptor(self: *const Self) vk.DescriptorSet {
    return self.sceneDescriptorSets[self.swapchain.image_index];
}

pub fn beginRender(self: *Self, sceneExtent: vk.Extent2D) !void {
    try beginRecordCommandBuffer(&self.gc, self.getCommandBuffer());

    drawTriangle(
        &self.gc,
        self.triangleBuffer,
        sceneExtent,
        self.sceneRenderPass,
        self.pipeline,
        self.sceneFrameBuffers[self.swapchain.image_index],
        self.getCommandBuffer(),
    );
    prepareImgui(
        &self.gc,
        self.swapchain.extent,
        self.mainRenderPass,
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
        self.framebuffers = try createFramebuffers(&self.gc, self.allocator, self.mainRenderPass, self.swapchain);

        destroyCommandBuffers(&self.gc, self.commandPool, self.allocator, self.commandBuffers);
        self.commandBuffers = try createCommandBuffers(
            &self.gc,
            self.commandPool,
            self.allocator,
            self.framebuffers,
        );
    }
}
