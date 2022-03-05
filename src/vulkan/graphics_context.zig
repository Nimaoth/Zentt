const std = @import("std");
const vk = @import("vulkan");
const c = @import("c.zig");
const sdl = @import("../sdl.zig");
const Allocator = std.mem.Allocator;

const required_device_extensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .createDevice = true,
    .destroySurfaceKHR = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getDeviceProcAddr = true,
});

const DeviceDispatch = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .createSemaphore = true,
    .createFence = true,
    .createImageView = true,
    .destroyImageView = true,
    .createImage = true,
    .destroyImage = true,
    .destroySemaphore = true,
    .destroyFence = true,
    .getSwapchainImagesKHR = true,
    .createSwapchainKHR = true,
    .destroySwapchainKHR = true,
    .acquireNextImageKHR = true,
    .deviceWaitIdle = true,
    .waitForFences = true,
    .resetFences = true,
    .queueSubmit = true,
    .queuePresentKHR = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .freeCommandBuffers = true,
    .queueWaitIdle = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .createRenderPass = true,
    .destroyRenderPass = true,
    .createGraphicsPipelines = true,
    .destroyPipeline = true,
    .createFramebuffer = true,
    .destroyFramebuffer = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .allocateMemory = true,
    .freeMemory = true,
    .createBuffer = true,
    .destroyBuffer = true,
    .getBufferMemoryRequirements = true,
    .mapMemory = true,
    .unmapMemory = true,
    .bindBufferMemory = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .cmdBindPipeline = true,
    .cmdDraw = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdBindVertexBuffers = true,
    .cmdCopyBuffer = true,
    .createDescriptorPool = true,
    .destroyDescriptorPool = true,
    .resetCommandPool = true,
    .getImageMemoryRequirements = true,
    .bindImageMemory = true,
    .allocateDescriptorSets = true,
    .createDescriptorSetLayout = true,
    .destroyDescriptorSetLayout = true,
    .updateDescriptorSets = true,
    .resetDescriptorPool = true,
    .createSampler = true,
    .destroySampler = true,
    .cmdBindDescriptorSets = true,
    .cmdPushConstants = true,
    .cmdPipelineBarrier = true,
    .cmdCopyBufferToImage = true,
});

pub const Buffer = struct {
    buffer: vk.Buffer,
    memory: vk.DeviceMemory,
    size: vk.DeviceSize,

    pub fn deinit(self: *const @This(), gc: *const GraphicsContext) void {
        gc.vkd.destroyBuffer(gc.dev, self.buffer, null);
        gc.vkd.freeMemory(gc.dev, self.memory, null);
    }
};

pub const Image = struct {
    image: vk.Image,
    memory: vk.DeviceMemory,

    pub fn deinit(self: *const @This(), gc: *GraphicsContext) void {
        gc.vkd.destroyImage(gc.dev, self.image, null);
        gc.vkd.freeMemory(gc.dev, self.memory, null);
    }
};

pub const GraphicsContext = struct {
    vkb: BaseDispatch,
    vki: InstanceDispatch,
    vkd: DeviceDispatch,

    instance: vk.Instance,
    surface: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    dev: vk.Device,
    graphics_queue: Queue,
    present_queue: Queue,

    command_pool: vk.CommandPool,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(allocator: Allocator, app_name: [*:0]const u8, window: *sdl.SDL_Window) !GraphicsContext {
        var self: GraphicsContext = undefined;
        self.vkb = try BaseDispatch.load(sdl.SDL_Vulkan_GetVkGetInstanceProcAddrZig());

        var glfw_exts_count: u32 = 0;
        if (sdl.SDL_Vulkan_GetInstanceExtensions(window, &glfw_exts_count, null) != sdl.SDL_TRUE) {
            return error.FailedToGetSDLExtensions;
        }
        var glfw_exts: [][*:0]const u8 = try allocator.alloc([*:0]const u8, glfw_exts_count);
        defer allocator.free(glfw_exts);
        if (sdl.SDL_Vulkan_GetInstanceExtensions(window, &glfw_exts_count, glfw_exts.ptr) != sdl.SDL_TRUE) {
            return error.FailedToGetSDLExtensions;
        }

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = app_name,
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        };

        var layers = try std.ArrayList([*:0]const u8).initCapacity(allocator, 1);
        defer layers.deinit();
        if (@import("build_options").vulkan_validation) {
            std.log.info("Enabling vulkan validation layer.", .{});
            try layers.append("VK_LAYER_KHRONOS_validation");
        }
        self.instance = try self.vkb.createInstance(&.{
            .flags = .{},
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(u32, layers.items.len),
            .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.items.ptr),
            .enabled_extension_count = glfw_exts_count,
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, glfw_exts.ptr),
        }, null);

        self.vki = try InstanceDispatch.load(self.instance, sdl.SDL_Vulkan_GetVkGetInstanceProcAddrZig());
        errdefer self.vki.destroyInstance(self.instance, null);

        self.surface = try createSurface(self.instance, window);
        errdefer self.vki.destroySurfaceKHR(self.instance, self.surface, null);

        const candidate = try pickPhysicalDevice(self.vki, self.instance, allocator, self.surface);
        self.pdev = candidate.pdev;
        self.props = candidate.props;
        self.dev = try initializeCandidate(self.vki, candidate);
        self.vkd = try DeviceDispatch.load(self.dev, self.vki.dispatch.vkGetDeviceProcAddr);
        errdefer self.vkd.destroyDevice(self.dev, null);

        try logSupportedFormats(self.vki, self.pdev, allocator, self.surface);

        self.graphics_queue = Queue.init(self.vkd, self.dev, candidate.queues.graphics_family);
        self.present_queue = Queue.init(self.vkd, self.dev, candidate.queues.present_family);

        self.mem_props = self.vki.getPhysicalDeviceMemoryProperties(self.pdev);

        self.command_pool = try self.vkd.createCommandPool(self.dev, &.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = self.graphics_queue.family,
        }, null);
        errdefer self.vkd.destroyCommandPool(self.dev, self.command_pool, null);

        self.descriptor_pool = try self.createDescriptorPool();
        errdefer self.vkd.destroyDescriptorPool(self.dev, self.descriptor_pool, null);

        return self;
    }

    pub fn deinit(self: *GraphicsContext) void {
        self.vkd.destroyDescriptorPool(self.dev, self.descriptor_pool, null);
        self.vkd.destroyCommandPool(self.dev, self.command_pool, null);
        self.vkd.destroyDevice(self.dev, null);
        self.vki.destroySurfaceKHR(self.instance, self.surface, null);
        self.vki.destroyInstance(self.instance, null);
    }

    pub fn deviceName(self: *GraphicsContext) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.props.device_name, 0).?;
        return self.props.device_name[0..len];
    }

    pub fn findMemoryTypeIndex(self: *GraphicsContext, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count]) |mem_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(u5, i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(u32, i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: *GraphicsContext, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try self.vkd.allocateMemory(self.dev, &.{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }

    pub fn createDescriptorPool(gc: *const GraphicsContext) !vk.DescriptorPool {
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

    pub fn resetDescriptorPool(self: *GraphicsContext, descriptor_pool: vk.DescriptorPool, flags: vk.DescriptorPoolResetFlags) void {
        const result = self.vkd.dispatch.vkResetDescriptorPool(self.dev, descriptor_pool, flags.toInt());
        switch (result) {
            .success => {},
            else => unreachable,
        }
    }

    pub fn createImage(self: *GraphicsContext, width: u32, height: u32, format: vk.Format, tiling: vk.ImageTiling, usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags) !Image {
        var createInfo: vk.ImageCreateInfo = undefined;
        std.mem.set(u8, std.mem.asBytes(&createInfo), 0);
        createInfo.s_type = .image_create_info;
        createInfo.image_type = .@"2d";
        createInfo.format = format;
        createInfo.extent = .{ .width = width, .height = height, .depth = 1 };
        createInfo.mip_levels = 1;
        createInfo.array_layers = 1;
        createInfo.samples = .{ .@"1_bit" = true };
        createInfo.tiling = tiling;
        createInfo.usage = usage;
        createInfo.sharing_mode = .exclusive;
        createInfo.initial_layout = .@"undefined";

        const image = try self.vkd.createImage(self.dev, &createInfo, null);
        errdefer self.vkd.destroyImage(self.dev, image, null);

        const mem_reqs = self.vkd.getImageMemoryRequirements(self.dev, image);
        const mem_type_index = try self.findMemoryTypeIndex(mem_reqs.memory_type_bits, properties);
        const memory = try self.vkd.allocateMemory(self.dev, &.{
            .allocation_size = mem_reqs.size,
            .memory_type_index = mem_type_index,
        }, null);
        errdefer self.vkd.freeMemory(self.dev, memory, null);

        try self.vkd.bindImageMemory(self.dev, image, memory, 0);

        return Image{ .image = image, .memory = memory };
    }

    pub fn transitionImageToLayout(self: *GraphicsContext, image: Image, format: vk.Format, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout) !void {
        _ = format;

        const cmdbuf = try self.beginSingleTimeCommandBuffer();

        var barrier = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image.image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        var src_stage = vk.PipelineStageFlags{};
        var dst_stage = vk.PipelineStageFlags{};

        if (old_layout == .@"undefined" and new_layout == .transfer_dst_optimal) {
            barrier.src_access_mask = .{};
            barrier.dst_access_mask = .{ .transfer_write_bit = true };
            src_stage = .{ .top_of_pipe_bit = true };
            dst_stage = .{ .transfer_bit = true };
        } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) {
            barrier.src_access_mask = .{ .transfer_write_bit = true };
            barrier.dst_access_mask = .{ .shader_read_bit = true };
            src_stage = .{ .transfer_bit = true };
            dst_stage = .{ .fragment_shader_bit = true };
        } else {
            return error.UnsupportedTransition;
        }

        self.vkd.cmdPipelineBarrier(
            cmdbuf,
            src_stage,
            dst_stage,
            .{},
            0,
            undefined,
            0,
            undefined,
            1,
            @ptrCast([*]const vk.ImageMemoryBarrier, &barrier),
        );

        try self.endSingleTimeCommandBuffer(cmdbuf);
    }

    pub fn copyBufferToImage(self: *GraphicsContext, buffer: Buffer, image: Image, width: u32, height: u32) !void {
        const cmdbuf = try self.beginSingleTimeCommandBuffer();

        const region = vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = .{ .width = width, .height = height, .depth = 1 },
        };
        self.vkd.cmdCopyBufferToImage(
            cmdbuf,
            buffer.buffer,
            image.image,
            .transfer_dst_optimal,
            1,
            @ptrCast([*]const vk.BufferImageCopy, &region),
        );
        try self.endSingleTimeCommandBuffer(cmdbuf);
    }

    pub fn createBuffer(self: *GraphicsContext, size: u64, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags) !Buffer {
        const buffer = try self.vkd.createBuffer(self.dev, &.{
            .flags = .{},
            .size = size,
            .usage = usage,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
        }, null);
        errdefer self.vkd.destroyBuffer(self.dev, buffer, null);

        const mem_reqs = self.vkd.getBufferMemoryRequirements(self.dev, buffer);
        const memory = try self.allocate(mem_reqs, properties);
        errdefer self.vkd.freeMemory(self.dev, memory, null);

        try self.vkd.bindBufferMemory(self.dev, buffer, memory, 0);

        return Buffer{ .buffer = buffer, .memory = memory, .size = size };
    }

    pub fn uploadBufferData(self: *GraphicsContext, buffer: Buffer, data: []const u8) !void {
        const mem_raw = try self.vkd.mapMemory(self.dev, buffer.memory, 0, vk.WHOLE_SIZE, .{});
        const mem = @ptrCast([*]u8, mem_raw)[0..data.len];
        defer self.vkd.unmapMemory(self.dev, buffer.memory);

        if (mem.len < data.len) {
            std.log.err("uploadBufferData: data of size {} bytes does not fit in buffer with size {} bytes", .{ data.len, mem.len });
            return error.DataDoesNotFitInBuffer;
        }

        std.mem.copy(u8, mem, data);
    }

    pub fn uploadBufferDataStaged(self: *GraphicsContext, buffer: Buffer, data: []const u8) !void {
        const staging_buffer = try self.createBuffer(data.len, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
        defer staging_buffer.deinit(self);
        try self.uploadBufferData(staging_buffer, data);
        try self.copyBuffer(buffer.buffer, staging_buffer.buffer, data.len);
    }

    fn copyBuffer(gc: *GraphicsContext, dst: vk.Buffer, src: vk.Buffer, size: vk.DeviceSize) !void {
        var cmdbuf = try gc.beginSingleTimeCommandBuffer();

        const region = vk.BufferCopy{
            .src_offset = 0,
            .dst_offset = 0,
            .size = size,
        };
        gc.vkd.cmdCopyBuffer(cmdbuf, src, dst, 1, @ptrCast([*]const vk.BufferCopy, &region));

        try gc.endSingleTimeCommandBuffer(cmdbuf);
    }

    pub fn beginSingleTimeCommandBuffer(self: *GraphicsContext) !vk.CommandBuffer {
        var cmdbuf: vk.CommandBuffer = .null_handle;

        try self.vkd.allocateCommandBuffers(self.dev, &.{
            .command_pool = self.command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast([*]vk.CommandBuffer, &cmdbuf));
        errdefer self.vkd.freeCommandBuffers(self.dev, self.command_pool, 1, @ptrCast([*]const vk.CommandBuffer, &cmdbuf));

        try self.vkd.beginCommandBuffer(cmdbuf, &.{
            .flags = .{ .one_time_submit_bit = true },
            .p_inheritance_info = null,
        });

        return cmdbuf;
    }

    pub fn endSingleTimeCommandBuffer(self: *GraphicsContext, cmdbuf: vk.CommandBuffer) !void {
        try self.vkd.endCommandBuffer(cmdbuf);
        const si = vk.SubmitInfo{
            .wait_semaphore_count = 0,
            .p_wait_semaphores = undefined,
            .p_wait_dst_stage_mask = undefined,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &cmdbuf),
            .signal_semaphore_count = 0,
            .p_signal_semaphores = undefined,
        };
        try self.vkd.queueSubmit(self.graphics_queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &si), .null_handle);
        try self.vkd.queueWaitIdle(self.graphics_queue.handle);
        self.vkd.freeCommandBuffers(self.dev, self.command_pool, 1, @ptrCast([*]const vk.CommandBuffer, &cmdbuf));
    }
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(vkd: DeviceDispatch, dev: vk.Device, family: u32) Queue {
        return .{
            .handle = vkd.getDeviceQueue(dev, family, 0),
            .family = family,
        };
    }
};

fn createSurface(instance: vk.Instance, window: *sdl.SDL_Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    // if (c.glfwCreateWindowSurface(instance, window, null, &surface) != .success) {
    //     return error.SurfaceInitFailed;
    // }

    if (sdl.SDL_Vulkan_CreateSurface(window, instance, &surface) != sdl.SDL_TRUE) {
        return error.SurfaceInitFailed;
    }

    return surface;
}

fn initializeCandidate(vki: InstanceDispatch, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .flags = .{},
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .flags = .{},
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1
    else
        2;

    return try vki.createDevice(candidate.pdev, &.{
        .flags = .{},
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, &required_device_extensions),
        .p_enabled_features = null,
    }, null);
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

fn pickPhysicalDevice(
    vki: InstanceDispatch,
    instance: vk.Instance,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !DeviceCandidate {
    var device_count: u32 = undefined;
    _ = try vki.enumeratePhysicalDevices(instance, &device_count, null);

    const pdevs = try allocator.alloc(vk.PhysicalDevice, device_count);
    defer allocator.free(pdevs);

    _ = try vki.enumeratePhysicalDevices(instance, &device_count, pdevs.ptr);

    for (pdevs) |pdev| {
        if (try checkSuitable(vki, pdev, allocator, surface)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    vki: InstanceDispatch,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    const props = vki.getPhysicalDeviceProperties(pdev);

    if (!try checkExtensionSupport(vki, pdev, allocator)) {
        return null;
    }

    if (!try checkSurfaceSupport(vki, pdev, surface)) {
        return null;
    }

    if (try allocateQueues(vki, pdev, allocator, surface)) |allocation| {
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn logSupportedFormats(vki: InstanceDispatch, pdev: vk.PhysicalDevice, allocator: Allocator, surface: vk.SurfaceKHR) !void {
    var format_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);
    const formats = try allocator.alloc(vk.SurfaceFormatKHR, format_count);
    defer allocator.free(formats);
    _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, formats.ptr);
    std.log.scoped(.Vulkan).info("Supported formats: {any}", .{formats});
}

fn allocateQueues(vki: InstanceDispatch, pdev: vk.PhysicalDevice, allocator: Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    var family_count: u32 = undefined;
    vki.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, null);

    const families = try allocator.alloc(vk.QueueFamilyProperties, family_count);
    defer allocator.free(families);
    vki.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, families.ptr);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families) |properties, i| {
        const family = @intCast(u32, i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try vki.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(vki: InstanceDispatch, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    vki: InstanceDispatch,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
) !bool {
    var count: u32 = undefined;
    _ = try vki.enumerateDeviceExtensionProperties(pdev, null, &count, null);

    const propsv = try allocator.alloc(vk.ExtensionProperties, count);
    defer allocator.free(propsv);

    _ = try vki.enumerateDeviceExtensionProperties(pdev, null, &count, propsv.ptr);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            const len = std.mem.indexOfScalar(u8, &props.extension_name, 0).?;
            const prop_ext_name = props.extension_name[0..len];
            if (std.mem.eql(u8, std.mem.span(ext), prop_ext_name)) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}
