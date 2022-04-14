const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const sdl = @import("sdl.zig");

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Image = @import("vulkan/graphics_context.zig").Image;
const Buffer = @import("vulkan/graphics_context.zig").Buffer;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;

pub const scene_render_extent = vk.Extent2D{ .width = 2560, .height = 1440 };

const Self = @This();

pub const SceneImage = struct {
    image: Image,
    image_view: vk.ImageView,
    descriptor: vk.DescriptorSet,
    framebuffer: vk.Framebuffer,

    depth_image: Image,
    depth_image_view: vk.ImageView,

    id_image: Image,
    id_image_view: vk.ImageView,

    pub fn deinit(self: *const @This(), gc: *GraphicsContext) void {
        gc.vkd.destroyFramebuffer(gc.dev, self.framebuffer, null);
        gc.vkd.destroyImageView(gc.dev, self.image_view, null);
        self.image.deinit(gc);
        gc.vkd.destroyImageView(gc.dev, self.id_image_view, null);
        self.id_image.deinit(gc);
        gc.vkd.destroyImageView(gc.dev, self.depth_image_view, null);
        self.depth_image.deinit(gc);
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

last_rendered_id_index: u64,
id_staging_image: Buffer,

/// Render pass which renders to the image in `sceneImages`.
sceneRenderPass: vk.RenderPass,

/// Extent of the currently rendered scene images (so size of viewport basically).
current_scene_extent: vk.Extent2D,

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
    const sceneExtent = scene_render_extent;
    self.sceneRenderPass = try createSceneRenderPass(&self.gc, self.swapchain.surface_format.format);
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

    self.id_staging_image = try self.gc.createBuffer(
        sceneExtent.width * sceneExtent.height * 4,
        .{ .transfer_dst_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    errdefer self.id_staging_image.deinit(&self.gc);
    self.last_rendered_id_index = 0;

    return self;
}

pub fn deinit(self: *Self) void {
    destroyCommandBuffers(&self.gc, self.commandPool, self.allocator, self.commandBuffers);
    self.gc.vkd.destroyCommandPool(self.gc.dev, self.commandPool, null);

    self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.descriptorPool, null);
    self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, self.mainDescriptorSetLayout, null);
    self.gc.vkd.destroySampler(self.gc.dev, self.mainImageSampler, null);

    // scene
    self.id_staging_image.deinit(&self.gc);
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

pub fn getIdAt(self: *Self, x: usize, y: usize) !u64 {
    const id_image = self.sceneImages[self.last_rendered_id_index].id_image;

    const cmdbuf = try self.gc.beginSingleTimeCommandBuffer();

    const regions = [_]vk.BufferImageCopy{.{
        .buffer_offset = 0,
        .buffer_row_length = id_image.extent.width,
        .buffer_image_height = id_image.extent.height,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = id_image.extent,
    }};
    self.gc.vkd.cmdCopyImageToBuffer(cmdbuf, id_image.image, .transfer_src_optimal, self.id_staging_image.buffer, regions.len, @ptrCast([*]const vk.BufferImageCopy, &regions));

    try self.gc.endSingleTimeCommandBuffer(cmdbuf);

    //
    const mem_raw = try self.gc.vkd.mapMemory(self.gc.dev, self.id_staging_image.memory, 0, vk.WHOLE_SIZE, .{});
    const mem = @ptrCast([*]u8, mem_raw)[0 .. id_image.extent.width * id_image.extent.height * 4];
    defer self.gc.vkd.unmapMemory(self.gc.dev, self.id_staging_image.memory);

    const byte_index = (x + y * id_image.extent.width) * @sizeOf(u32);
    var id: u32 = 0;
    std.mem.copy(u8, std.mem.asBytes(&id), mem[byte_index .. byte_index + @sizeOf(u32)]);

    return id;
}

const CurrentFrame = struct { cmdbuf: vk.CommandBuffer, frame_index: u64 };
pub fn beginSceneRender(
    self: *Self,
    sceneExtent: vk.Extent2D,
) !CurrentFrame {
    self.current_scene_extent = sceneExtent;

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
    const clear = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 0.1, 0.1, 0.1, 1 } } },
        .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
        .{ .color = .{ .uint_32 = .{ 0, 0, 0, 0 } } },
    };

    self.gc.vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = self.sceneRenderPass,
        .framebuffer = self.sceneImages[self.swapchain.image_index].framebuffer,
        .render_area = render_area,
        .clear_value_count = clear.len,
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

pub fn endMainRender(self: *Self, window: *sdl.SDL_Window, new_extent: vk.Extent2D) !void {
    const cmdbuf = self.commandBuffers[self.swapchain.image_index];
    self.gc.vkd.cmdEndRenderPass(cmdbuf);
    try self.gc.vkd.endCommandBuffer(cmdbuf);

    self.last_rendered_id_index = self.swapchain.image_index;

    const state = self.swapchain.present(cmdbuf) catch |err| switch (err) {
        error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
        else => |narrow| return narrow,
    };

    if (state == .suboptimal or self.swapchain.extent.width != @intCast(u32, new_extent.width) or self.swapchain.extent.height != @intCast(u32, new_extent.height)) {
        var actual_extent = vk.Extent2D{ .width = 0, .height = 0 };
        while (actual_extent.width == 0 or actual_extent.height == 0) {
            var w: c_int = undefined;
            var h: c_int = undefined;
            sdl.SDL_Vulkan_GetDrawableSize(window, &w, &h);
            actual_extent = .{ .width = @intCast(u32, w), .height = @intCast(u32, h) };
            _ = sdl.SDL_WaitEvent(null);
        }

        try self.gc.vkd.deviceWaitIdle(self.gc.dev);

        try self.swapchain.recreate(actual_extent);

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
    errdefer gc.vkd.destroyImageView(gc.dev, image_view, null);

    const depth_image = try gc.createImage(extent.width, extent.height, .d24_unorm_s8_uint, .optimal, .{ .depth_stencil_attachment_bit = true }, .{ .device_local_bit = true });
    errdefer depth_image.deinit(gc);

    const depth_image_view = try gc.vkd.createImageView(gc.dev, &.{
        .flags = .{},
        .image = depth_image.image,
        .view_type = .@"2d",
        .format = .d24_unorm_s8_uint,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .depth_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    errdefer gc.vkd.destroyImageView(gc.dev, depth_image_view, null);

    const id_image = try gc.createImage(extent.width, extent.height, .r32_uint, .optimal, .{ .transfer_src_bit = true, .color_attachment_bit = true }, .{ .device_local_bit = true });
    errdefer id_image.deinit(gc);

    const id_image_view = try gc.vkd.createImageView(gc.dev, &.{
        .flags = .{},
        .image = id_image.image,
        .view_type = .@"2d",
        .format = .r32_uint,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    errdefer gc.vkd.destroyImageView(gc.dev, id_image_view, null);

    const framebuffer = try createSceneFrameBuffer(gc, render_pass, &.{ image_view, depth_image_view, id_image_view }, extent);
    errdefer gc.vkd.destroyFramebuffer(gc.dev, framebuffer, null);

    const descriptor = try createSceneImageDescriptorSet(gc, image_view, descriptor_pool, descriptor_set_layout, sampler);

    return SceneImage{
        .image = image,
        .image_view = image_view,
        .depth_image = depth_image,
        .depth_image_view = depth_image_view,
        .id_image = id_image,
        .id_image_view = id_image_view,
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

fn createSceneFrameBuffer(gc: *GraphicsContext, render_pass: vk.RenderPass, image_views: []const vk.ImageView, extent: vk.Extent2D) !vk.Framebuffer {
    return try gc.vkd.createFramebuffer(gc.dev, &.{
        .flags = .{},
        .render_pass = render_pass,
        .attachment_count = @intCast(u32, image_views.len),
        .p_attachments = @ptrCast([*]const vk.ImageView, image_views.ptr),
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

fn createSceneRenderPass(gc: *GraphicsContext, format: vk.Format) !vk.RenderPass {
    const color_attachments = [_]vk.AttachmentDescription{
        .{
            .flags = .{},
            .format = format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .@"undefined",
            .final_layout = .shader_read_only_optimal,
        },
        .{
            .flags = .{},
            .format = .d24_unorm_s8_uint,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .@"undefined",
            .final_layout = .depth_stencil_attachment_optimal,
        },
        .{
            .flags = .{},
            .format = .r32_uint,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .@"undefined",
            .final_layout = .transfer_src_optimal,
        },
    };

    const color_attachment_refs = [_]vk.AttachmentReference{
        .{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        },
        .{
            .attachment = 2,
            .layout = .color_attachment_optimal,
        },
    };

    const depth_attachment_ref = vk.AttachmentReference{
        .attachment = 1,
        .layout = .depth_stencil_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .flags = .{},
        .pipeline_bind_point = .graphics,
        .input_attachment_count = 0,
        .p_input_attachments = undefined,
        .color_attachment_count = color_attachment_refs.len,
        .p_color_attachments = @ptrCast([*]const vk.AttachmentReference, &color_attachment_refs),
        .p_resolve_attachments = null,
        .p_depth_stencil_attachment = &depth_attachment_ref,
        .preserve_attachment_count = 0,
        .p_preserve_attachments = undefined,
    };

    const dependency = vk.SubpassDependency{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = vk.PipelineStageFlags{ .fragment_shader_bit = true, .early_fragment_tests_bit = true },
        .dst_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
        .src_access_mask = vk.AccessFlags{ .shader_read_bit = true },
        .dst_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true, .depth_stencil_attachment_write_bit = true },
        .dependency_flags = vk.DependencyFlags{},
    };

    return try gc.vkd.createRenderPass(gc.dev, &.{
        .flags = .{},
        .attachment_count = color_attachments.len,
        .p_attachments = @ptrCast([*]const vk.AttachmentDescription, &color_attachments),
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
