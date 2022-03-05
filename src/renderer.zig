const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const sdl = @import("sdl.zig");
const stb = @import("stb_image.zig");

const imgui2 = @import("imgui2.zig");

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Image = @import("vulkan/graphics_context.zig").Image;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const Pipeline = @import("vulkan/pipeline.zig");
const resources = @import("resources");

const zal = @import("zalgebra");

const Self = @This();
const Renderer = @This();

pub const SceneImage = struct {
    image: Image,
    image_view: vk.ImageView,
    descriptor: vk.DescriptorSet,
    framebuffer: vk.Framebuffer,

    pub fn deinit(self: *const @This(), gc: *GraphicsContext) void {
        gc.vkd.destroyFramebuffer(gc.dev, self.framebuffer, null);
        gc.vkd.destroyImageView(gc.dev, self.image_view, null);
        self.image.deinit(gc);
    }
};

allocator: Allocator,
gc: GraphicsContext,

/// Global command pool.
commandPool: vk.CommandPool,

/// Descriptor pool currently only used for the framebuffer images to bind them in the main render pass
/// which renders to the swapchain image.
descriptorPool: vk.DescriptorPool,

// Swapchain. Contains multiple images. Must be recreated when the window size changes.
swapchain: Swapchain,

/// Main render pass which renders to the swapchain images.
mainRenderPass: vk.RenderPass,

/// Layout for the scene images when bound in the main render pass which renders to the swapchain image.
mainDescriptorSetLayout: vk.DescriptorSetLayout,

/// Sample used for scene images when bound in the main render pass which renders to the swapchain image.
mainImageSampler: vk.Sampler,

/// One frame buffer for every image in the swapchain. Must be recreated when the window size changes.
framebuffers: []vk.Framebuffer,

/// One command buffer for every image in the swapchain. Must be recreated when the window size changes.
commandBuffers: []vk.CommandBuffer,

/// One image+framebuffer+descriptor for every image in the swapchain
/// We render the scene to these images and then render the images to the swapchain using imgui atm.
/// These currently have a fixed size of 1980x1080, and we specify the area we render to every frame.
/// Maybe it's better to recreate them aswell when the viewport size changes.
sceneImages: []SceneImage,

/// Render pass which renders to the image in `sceneImages`.
sceneRenderPass: vk.RenderPass,

pub fn init(allocator: Allocator, window: *sdl.SDL_Window, extent: vk.Extent2D) !*Self {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;

    self.gc = try GraphicsContext.init(allocator, "App", window);
    errdefer self.gc.deinit();

    std.debug.print("Using device: {s}\n", .{self.gc.deviceName()});

    self.swapchain = try Swapchain.init(&self.gc, allocator, extent);
    errdefer self.swapchain.deinit();

    self.descriptorPool = try self.gc.createDescriptorPool();
    errdefer self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.descriptorPool, null);

    self.commandPool = try self.gc.vkd.createCommandPool(self.gc.dev, &.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = self.gc.graphics_queue.family,
    }, null);
    errdefer self.gc.vkd.destroyCommandPool(self.gc.dev, self.commandPool, null);

    self.commandBuffers = try createCommandBuffers(
        &self.gc,
        self.commandPool,
        allocator,
        self.swapchain.swap_images.len,
    );
    errdefer destroyCommandBuffers(&self.gc, self.commandPool, allocator, self.commandBuffers);

    // main render pass
    self.mainRenderPass = try createRenderPass(&self.gc, self.swapchain.surface_format.format, .present_src_khr);
    errdefer self.gc.vkd.destroyRenderPass(self.gc.dev, self.mainRenderPass, null);

    self.framebuffers = try createFramebuffers(&self.gc, allocator, self.mainRenderPass, self.swapchain);
    errdefer destroyFramebuffers(&self.gc, allocator, self.framebuffers);

    // scene render pass
    const sceneExtent = vk.Extent2D{ .width = 1920, .height = 1080 };
    self.sceneRenderPass = try createSceneRenderPass(&self.gc, self.swapchain.surface_format.format, .shader_read_only_optimal);
    errdefer self.gc.vkd.destroyRenderPass(self.gc.dev, self.sceneRenderPass, null);

    self.mainImageSampler = try createMainImageSampler(&self.gc);
    errdefer self.gc.vkd.destroySampler(self.gc.dev, self.mainImageSampler, null);

    self.mainDescriptorSetLayout = try createMainDescriptorSetLayout(&self.gc);
    errdefer self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, self.mainDescriptorSetLayout, null);

    self.sceneImages = try createSceneImages(
        &self.gc,
        allocator,
        self.swapchain.swap_images.len,
        self.swapchain.surface_format.format,
        sceneExtent,
        self.sceneRenderPass,
        self.descriptorPool,
        self.mainDescriptorSetLayout,
        self.mainImageSampler,
    );
    errdefer destroySceneImages(&self.gc, allocator, self.sceneImages);

    return self;
}

pub fn deinit(self: *Self) void {
    destroyCommandBuffers(&self.gc, self.commandPool, self.allocator, self.commandBuffers);
    self.gc.vkd.destroyCommandPool(self.gc.dev, self.commandPool, null);

    self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.descriptorPool, null);
    self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, self.mainDescriptorSetLayout, null);
    self.gc.vkd.destroySampler(self.gc.dev, self.mainImageSampler, null);

    // scene
    destroySceneImages(&self.gc, self.allocator, self.sceneImages);

    // main
    destroyFramebuffers(&self.gc, self.allocator, self.framebuffers);
    self.gc.vkd.destroyRenderPass(self.gc.dev, self.mainRenderPass, null);
    self.gc.vkd.destroyRenderPass(self.gc.dev, self.sceneRenderPass, null);
    self.swapchain.deinit();
    self.gc.deinit();

    self.allocator.destroy(self);
}

pub fn getCommandBuffer(self: *const Self) vk.CommandBuffer {
    return self.commandBuffers[self.swapchain.image_index];
}

pub fn getSceneImage(self: *const Self) *SceneImage {
    return &self.sceneImages[self.swapchain.image_index];
}

const CurrentFrame = struct { cmdbuf: vk.CommandBuffer, frame_index: u64 };
pub fn beginSceneRender(
    self: *Self,
    sceneExtent: vk.Extent2D,
) !CurrentFrame {
    const cmdbuf = self.getCommandBuffer();
    try self.gc.vkd.beginCommandBuffer(cmdbuf, &.{
        .flags = .{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    });

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @intToFloat(f32, sceneExtent.width),
        .height = @intToFloat(f32, sceneExtent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = sceneExtent,
    };

    self.gc.vkd.cmdSetViewport(cmdbuf, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));
    self.gc.vkd.cmdSetScissor(cmdbuf, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));

    // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = sceneExtent,
    };
    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 0.1, 0.1, 0.1, 1 } },
    };

    self.gc.vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = self.sceneRenderPass,
        .framebuffer = self.sceneImages[self.swapchain.image_index].framebuffer,
        .render_area = render_area,
        .clear_value_count = 1,
        .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear),
    }, .@"inline");

    return CurrentFrame{ .cmdbuf = cmdbuf, .frame_index = self.swapchain.image_index };
}

pub fn endSceneRender(self: *Self) !void {
    const cmdbuf = self.getCommandBuffer();
    self.gc.vkd.cmdEndRenderPass(cmdbuf);
}

pub fn beginMainRender(self: *Self) !void {
    prepareImgui(
        &self.gc,
        self.swapchain.extent,
        self.mainRenderPass,
        self.framebuffers[self.swapchain.image_index],
        self.getCommandBuffer(),
    );
}

fn prepareImgui(
    gc: *GraphicsContext,
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

pub fn endMainRender(self: *Self, newExtent: vk.Extent2D) !void {
    const cmdbuf = self.commandBuffers[self.swapchain.image_index];
    self.gc.vkd.cmdEndRenderPass(cmdbuf);
    try self.gc.vkd.endCommandBuffer(cmdbuf);

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
            self.framebuffers.len,
        );
    }
}

// ----------------------------- helpers ---------------------------------

fn createCommandBuffers(
    gc: *GraphicsContext,
    pool: vk.CommandPool,
    allocator: Allocator,
    count: u64,
) ![]vk.CommandBuffer {
    const commandBuffers = try allocator.alloc(vk.CommandBuffer, count);
    errdefer allocator.free(commandBuffers);

    try gc.vkd.allocateCommandBuffers(gc.dev, &.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = @truncate(u32, commandBuffers.len),
    }, commandBuffers.ptr);
    errdefer gc.vkd.freeCommandBuffers(gc.dev, pool, @truncate(u32, commandBuffers.len), commandBuffers.ptr);

    return commandBuffers;
}

fn destroyCommandBuffers(gc: *GraphicsContext, pool: vk.CommandPool, allocator: Allocator, commandBuffers: []vk.CommandBuffer) void {
    gc.vkd.freeCommandBuffers(gc.dev, pool, @truncate(u32, commandBuffers.len), commandBuffers.ptr);
    allocator.free(commandBuffers);
}

fn createSceneImages(
    gc: *GraphicsContext,
    allocator: Allocator,
    amount: usize,
    format: vk.Format,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set_layout: vk.DescriptorSetLayout,
    sampler: vk.Sampler,
) ![]SceneImage {
    const images = try allocator.alloc(SceneImage, amount);
    errdefer allocator.free(images);

    var i: usize = 0;
    errdefer for (images[0..i]) |img| {
        img.deinit(gc);
    };

    for (images) |*image| {
        image.* = try createSceneImage(gc, format, extent, render_pass, descriptor_pool, descriptor_set_layout, sampler);
        i += 1;
    }

    return images;
}

fn createSceneImage(
    gc: *GraphicsContext,
    format: vk.Format,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set_layout: vk.DescriptorSetLayout,
    sampler: vk.Sampler,
) !SceneImage {
    const image = try gc.createImage(extent.width, extent.height, format, .optimal, .{ .sampled_bit = true, .color_attachment_bit = true }, .{ .device_local_bit = true });
    errdefer image.deinit(gc);

    const image_view = try gc.vkd.createImageView(gc.dev, &.{
        .flags = .{},
        .image = image.image,
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

    const framebuffer = try createSceneFrameBuffer(gc, render_pass, image_view, extent);
    errdefer gc.vkd.destroyFramebuffer(gc.dev, framebuffer, null);

    const descriptor = try createSceneImageDescriptorSet(gc, image_view, descriptor_pool, descriptor_set_layout, sampler);

    return SceneImage{
        .image = image,
        .image_view = image_view,
        .descriptor = descriptor,
        .framebuffer = framebuffer,
    };
}

fn destroySceneImages(gc: *GraphicsContext, allocator: Allocator, images: []const SceneImage) void {
    for (images) |img| {
        img.deinit(gc);
    }
    allocator.free(images);
}

fn createSceneFrameBuffer(gc: *GraphicsContext, render_pass: vk.RenderPass, image_view: vk.ImageView, extent: vk.Extent2D) !vk.Framebuffer {
    return try gc.vkd.createFramebuffer(gc.dev, &.{
        .flags = .{},
        .render_pass = render_pass,
        .attachment_count = 1,
        .p_attachments = @ptrCast([*]const vk.ImageView, &image_view),
        .width = extent.width,
        .height = extent.height,
        .layers = 1,
    }, null);
}

fn createMainDescriptorSetLayout(gc: *GraphicsContext) !vk.DescriptorSetLayout {
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

fn createMainImageSampler(gc: *GraphicsContext) !vk.Sampler {
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

fn createSceneImageDescriptorSet(gc: *GraphicsContext, image_view: vk.ImageView, descriptor_pool: vk.DescriptorPool, descriptor_set_layout: vk.DescriptorSetLayout, sampler: vk.Sampler) !vk.DescriptorSet {
    var descriptor: vk.DescriptorSet = .null_handle;

    try gc.vkd.allocateDescriptorSets(gc.dev, &.{
        .descriptor_pool = descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &descriptor_set_layout),
    }, @ptrCast([*]vk.DescriptorSet, &descriptor));

    const desc_image = vk.DescriptorImageInfo{
        .sampler = sampler,
        .image_view = image_view,
        .image_layout = .shader_read_only_optimal,
    };

    var write_desc: vk.WriteDescriptorSet = undefined;
    std.mem.set(u8, std.mem.asBytes(&write_desc), 0);
    write_desc.s_type = .write_descriptor_set;
    write_desc.dst_set = descriptor;
    write_desc.dst_binding = 0;
    write_desc.dst_array_element = 0;
    write_desc.descriptor_count = 1;
    write_desc.descriptor_type = .combined_image_sampler;
    write_desc.p_image_info = @ptrCast([*]const vk.DescriptorImageInfo, &desc_image);

    gc.vkd.updateDescriptorSets(gc.dev, 1, @ptrCast([*]const vk.WriteDescriptorSet, &write_desc), 0, undefined);

    return descriptor;
}

fn createFramebuffers(gc: *GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
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

fn destroyFramebuffers(gc: *GraphicsContext, allocator: Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| gc.vkd.destroyFramebuffer(gc.dev, fb, null);
    allocator.free(framebuffers);
}

fn createSceneRenderPass(gc: *GraphicsContext, format: vk.Format, finalImageLayout: vk.ImageLayout) !vk.RenderPass {
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

fn createRenderPass(gc: *GraphicsContext, format: vk.Format, finalImageLayout: vk.ImageLayout) !vk.RenderPass {
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
