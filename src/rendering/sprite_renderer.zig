const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Image = @import("vulkan/graphics_context.zig").Image;
const Buffer = @import("vulkan/graphics_context.zig").Buffer;
const Pipeline = @import("vulkan/pipeline.zig");
const resources = @import("resources");

const AssetDB = @import("assetdb.zig");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Self = @This();

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
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "uv"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
    uv: [2]f32,
};

const vertices = [_]Vertex{
    .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 1, 1 }, .uv = .{ 0, 0 } },
    .{ .pos = .{ 0.5, -0.5 }, .color = .{ 1, 1, 1 }, .uv = .{ 1, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 1, 1, 1 }, .uv = .{ 1, 1 } },
    .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 1, 1 }, .uv = .{ 0, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 1, 1, 1 }, .uv = .{ 1, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 1, 1, 1 }, .uv = .{ 0, 1 } },
};

pub const SceneMatricesUbo = struct {
    view: Mat4,
    proj: Mat4,
};

pub const TextureAsset = struct {
    image: Image,
    image_view: vk.ImageView,
    descriptor: vk.DescriptorSet,

    pub fn deinit(self: *const @This(), gc: *GraphicsContext) void {
        gc.vkd.destroyImageView(gc.dev, self.image_view, null);
        self.image.deinit(gc);
    }
};

/// Contains data which needs exist per frame.
/// Because we might modify data from frame x+1 while frame x is still being rendered.
const FrameData = struct {
    gc: *GraphicsContext,

    /// Buffer containing view and projection matrices used in the shader.
    /// Updated once at the beginning of the frame using data from a camera.
    scene_matrices_ubo: Buffer,

    /// Descriptor set for accessing scene_matrices_ubo in the vertex shader.
    descriptor_set: vk.DescriptorSet,

    /// Used to allocate descriptor sets for textures used to draw sprites.
    /// Reset at the beginning of the frame, descriptor sets are allocated
    /// during the frame as needed.
    image_descriptor_pool: vk.DescriptorPool,

    /// Maps asset to descriptor set.
    /// Gets rebuilt every frame.
    image_descriptor_sets: std.AutoHashMap(*anyopaque, vk.DescriptorSet),

    last_bound_descriptor_set: vk.DescriptorSet = .null_handle,

    fn init(gc: *GraphicsContext, allocator: Allocator, descriptor_pool: vk.DescriptorPool, scene_matrices_layout: vk.DescriptorSetLayout) !FrameData {
        const scene_matrices_ubo = try gc.createBuffer(@sizeOf(SceneMatricesUbo), .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
        errdefer scene_matrices_ubo.deinit(gc);

        const descriptor_set = try createSceneDescriptorSet(gc, scene_matrices_ubo, descriptor_pool, scene_matrices_layout);

        const image_descriptor_pool = try gc.createDescriptorPool();

        return FrameData{
            .gc = gc,
            .scene_matrices_ubo = scene_matrices_ubo,
            .descriptor_set = descriptor_set,
            .image_descriptor_pool = image_descriptor_pool,
            .image_descriptor_sets = std.AutoHashMap(*anyopaque, vk.DescriptorSet).init(allocator),
        };
    }

    pub fn deinit(self: *FrameData) void {
        self.image_descriptor_sets.deinit();
        self.scene_matrices_ubo.deinit(self.gc);
        self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.image_descriptor_pool, null);
    }

    pub fn resetDescriptorPool(self: *FrameData) void {
        self.image_descriptor_sets.clearRetainingCapacity();
        self.gc.resetDescriptorPool(self.image_descriptor_pool, .{});
        self.last_bound_descriptor_set = .null_handle;
    }
};

allocator: Allocator,
gc: *GraphicsContext,

/// Layouts of the descriptor sets used by the quad_pipeline.
/// Set 0 (per frame): scene_matrices_ubo (view, proj matrices)
/// Set 1 (per quad): texture
sceneDescriptorSetLayouts: []vk.DescriptorSetLayout,

/// Pipeline which renders quads with a position and scale which is specified using push constants
/// And a texture with is bound using a descriptor set.
quad_pipeline: Pipeline,

/// Buffer containing the vertex data for a quad.
quad_buffer: Buffer,

/// Texture used for all quads drawn.
/// @todo: Specify this texture when submitting a sprite.
// texture: *TextureAsset,

/// Descriptor pool used for descriptors which can be used by multiple frames simultaneously.
global_descriptor_pool: vk.DescriptorPool,

/// Contains data for each frame (same length as swapchain images).
frame_data: []FrameData,

/// Current frame
cmdbuf: vk.CommandBuffer,
frame_index: u64,
matrices: SceneMatricesUbo,

pub fn init(allocator: Allocator, gc: *GraphicsContext, frame_count: u64, render_pass: vk.RenderPass) !*Self {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.gc = gc;

    self.global_descriptor_pool = try gc.createDescriptorPool();

    self.sceneDescriptorSetLayouts = try self.createSceneDescriptorSetLayout();
    errdefer {
        for (self.sceneDescriptorSetLayouts) |sceneDescriptorSetLayout| gc.vkd.destroyDescriptorSetLayout(gc.dev, sceneDescriptorSetLayout, null);
        allocator.free(self.sceneDescriptorSetLayouts);
    }

    self.frame_data = try self.createFrameData(frame_count);
    errdefer self.destroyFrameData();

    // pipeline
    const push_constants = [_]vk.PushConstantRange{
        .{
            .stage_flags = .{ .vertex_bit = true },
            .offset = 0,
            .size = @sizeOf(Mat4),
        },
        .{
            .stage_flags = .{ .fragment_bit = true },
            .offset = @sizeOf(Mat4),
            .size = @sizeOf(Vec4) + @sizeOf(Vec2) + @sizeOf(u32),
        },
    };
    self.quad_pipeline = try Pipeline.init(
        allocator,
        gc,
        render_pass,
        self.sceneDescriptorSetLayouts,
        push_constants[0..],
        resources.triangle_vert,
        resources.triangle_frag,
        &.{Vertex.binding_description},
        Vertex.attribute_description[0..],
    );
    errdefer self.deinit();

    self.quad_buffer = try gc.createBuffer(@sizeOf(@TypeOf(vertices)), .{ .transfer_dst_bit = true, .vertex_buffer_bit = true }, .{ .device_local_bit = true });
    try gc.uploadBufferDataStaged(self.quad_buffer, std.mem.sliceAsBytes(vertices[0..]));

    return self;
}

pub fn deinit(self: *Self) void {
    self.destroyFrameData();

    self.quad_buffer.deinit(self.gc);

    self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.global_descriptor_pool, null);
    for (self.sceneDescriptorSetLayouts) |sceneDescriptorSetLayout| self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, sceneDescriptorSetLayout, null);
    self.allocator.free(self.sceneDescriptorSetLayouts);

    self.quad_pipeline.deinit();

    self.allocator.destroy(self);
}

pub fn updateCameraData(self: *Self, matrices: *const SceneMatricesUbo) !void {
    self.matrices = matrices.*;
    const frame = &self.frame_data[self.frame_index];
    try self.gc.uploadBufferData(frame.scene_matrices_ubo, std.mem.asBytes(matrices));
}

pub fn beginRender(self: *Self, cmdbuf: vk.CommandBuffer, frame_index: u64) !void {
    self.cmdbuf = cmdbuf;
    self.frame_index = frame_index;

    const frame = &self.frame_data[frame_index];

    frame.resetDescriptorPool();

    // Bind descriptor set for scene matrices of current frame.
    self.gc.vkd.cmdBindDescriptorSets(cmdbuf, .graphics, self.quad_pipeline.layout, 0, 1, @ptrCast([*]const vk.DescriptorSet, &self.frame_data[frame_index].descriptor_set), 0, undefined);

    // Bind the pipeline
    self.gc.vkd.cmdBindPipeline(cmdbuf, .graphics, self.quad_pipeline.pipeline);

    // Bind the vertext buffer
    self.gc.vkd.cmdBindPipeline(cmdbuf, .graphics, self.quad_pipeline.pipeline);
    const offset = [_]vk.DeviceSize{0};
    self.gc.vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast([*]const vk.Buffer, &self.quad_buffer), &offset);
}

pub fn endRender(self: *Self) void {
    _ = self;
    // Nothing to do yet.
}

/// Draw a quad at the specified transform.
/// (X,Y) is the 2D position, (Z,W) is the 2D scale (scale of 1 means width and height are 1).
pub fn drawSprite(self: *Self, position: Vec3, size: Vec2, rotation: f32, texture: *AssetDB.TextureAsset, tiling: Vec2, id: u32) void {
    const frame = &self.frame_data[self.frame_index];

    var uv = texture.getUV();

    // Get a descriptor from the cache or create a new one.
    const descriptor = if (frame.image_descriptor_sets.get(texture)) |descriptor| descriptor else blk: {
        const image = texture.resolve();

        // Create new descriptor. This will be freed automatically at the beginning of the next time this frame is used.
        const descriptor = self.createDescriptorForImage(frame.image_descriptor_pool, image.image_view, image.sampler) catch |err| {
            std.log.err("Failed to create descriptor for texture: {}", .{err});
            return;
        };

        frame.image_descriptor_sets.put(texture, descriptor) catch |err| {
            std.log.err("Failed to cache descriptor set: {}", .{err});
        };

        break :blk descriptor;
    };

    if (descriptor != frame.last_bound_descriptor_set) {
        self.gc.vkd.cmdBindDescriptorSets(self.cmdbuf, .graphics, self.quad_pipeline.layout, 1, 1, @ptrCast([*]const vk.DescriptorSet, &descriptor), 0, undefined);
        frame.last_bound_descriptor_set = descriptor;
    }

    const transform_mat = Mat4.recompose(
        position,
        Vec3.new(0, 0, rotation),
        Vec3.new(size.x(), size.y(), 1),
    );

    self.gc.vkd.cmdPushConstants(self.cmdbuf, self.quad_pipeline.layout, .{ .vertex_bit = true }, 0, @sizeOf(Mat4), &transform_mat);
    self.gc.vkd.cmdPushConstants(self.cmdbuf, self.quad_pipeline.layout, .{ .fragment_bit = true }, @sizeOf(Mat4), @sizeOf(Vec4), &uv);
    self.gc.vkd.cmdPushConstants(self.cmdbuf, self.quad_pipeline.layout, .{ .fragment_bit = true }, @sizeOf(Mat4) + @sizeOf(Vec4), @sizeOf(Vec2), &tiling);
    self.gc.vkd.cmdPushConstants(self.cmdbuf, self.quad_pipeline.layout, .{ .fragment_bit = true }, @sizeOf(Mat4) + @sizeOf(Vec4) + @sizeOf(Vec2), @sizeOf(u32), &id);

    self.gc.vkd.cmdDraw(self.cmdbuf, vertices.len, 1, 0, 0);
}

// ----------------------------- helpers -----------------------------------

fn createSceneDescriptorSetLayout(self: *Self) ![]vk.DescriptorSetLayout {
    const result = try self.allocator.alloc(vk.DescriptorSetLayout, 2);
    errdefer self.allocator.free(result);

    const global_bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
            .p_immutable_samplers = null,
        },
    };

    result[0] = try self.gc.vkd.createDescriptorSetLayout(self.gc.dev, &.{
        .flags = .{},
        .binding_count = global_bindings.len,
        .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, &global_bindings),
    }, null);

    const object_bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = null,
        },
    };

    result[1] = try self.gc.vkd.createDescriptorSetLayout(self.gc.dev, &.{
        .flags = .{},
        .binding_count = object_bindings.len,
        .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, &object_bindings),
    }, null);

    return result;
}

fn createSceneDescriptorSet(gc: *GraphicsContext, buffer: Buffer, descriptorPool: vk.DescriptorPool, descriptorSetLayout: vk.DescriptorSetLayout) !vk.DescriptorSet {
    var descriptorSet: vk.DescriptorSet = .null_handle;
    try gc.vkd.allocateDescriptorSets(gc.dev, &.{
        .descriptor_pool = descriptorPool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &descriptorSetLayout),
    }, @ptrCast([*]vk.DescriptorSet, &descriptorSet));

    const desc = vk.DescriptorBufferInfo{
        .buffer = buffer.buffer,
        .offset = 0,
        .range = buffer.size,
    };

    var write_desc: vk.WriteDescriptorSet = undefined;
    std.mem.set(u8, std.mem.asBytes(&write_desc), 0);
    write_desc.s_type = .write_descriptor_set;
    write_desc.dst_set = descriptorSet;
    write_desc.dst_binding = 0;
    write_desc.dst_array_element = 0;
    write_desc.descriptor_count = 1;
    write_desc.descriptor_type = .uniform_buffer;
    write_desc.p_buffer_info = @ptrCast([*]const vk.DescriptorBufferInfo, &desc);

    gc.vkd.updateDescriptorSets(gc.dev, 1, @ptrCast([*]const vk.WriteDescriptorSet, &write_desc), 0, undefined);

    return descriptorSet;
}

fn createFrameData(self: *Self, num: u64) ![]FrameData {
    const frames = try self.allocator.alloc(FrameData, num);
    errdefer self.allocator.free(frames);
    for (frames) |*frame| {
        frame.* = try FrameData.init(self.gc, self.allocator, self.global_descriptor_pool, self.sceneDescriptorSetLayouts[0]);
    }
    return frames;
}

fn destroyFrameData(self: *Self) void {
    for (self.frame_data) |*frame| frame.deinit();
    self.allocator.free(self.frame_data);
}

fn createDescriptorForImage(self: *Self, pool: vk.DescriptorPool, image_view: vk.ImageView, sampler: vk.Sampler) !vk.DescriptorSet {
    const desc = vk.DescriptorImageInfo{
        .sampler = sampler,
        .image_view = image_view,
        .image_layout = .shader_read_only_optimal,
    };

    var descriptor: vk.DescriptorSet = .null_handle;
    try self.gc.vkd.allocateDescriptorSets(self.gc.dev, &.{
        .descriptor_pool = pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &self.sceneDescriptorSetLayouts[1]),
    }, @ptrCast([*]vk.DescriptorSet, &descriptor));

    var write_desc: vk.WriteDescriptorSet = undefined;
    std.mem.set(u8, std.mem.asBytes(&write_desc), 0);
    write_desc.s_type = .write_descriptor_set;
    write_desc.dst_set = descriptor;
    write_desc.dst_binding = 0;
    write_desc.dst_array_element = 0;
    write_desc.descriptor_count = 1;
    write_desc.descriptor_type = .combined_image_sampler;
    write_desc.p_image_info = @ptrCast([*]const vk.DescriptorImageInfo, &desc);

    self.gc.vkd.updateDescriptorSets(self.gc.dev, 1, @ptrCast([*]const vk.WriteDescriptorSet, &write_desc), 0, undefined);

    return descriptor;
}
