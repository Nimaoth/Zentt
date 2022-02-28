const std = @import("std");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const stb = @import("stb_image.zig");
const vk = @import("vulkan");
const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Image = @import("vulkan/graphics_context.zig").Image;

const Vec2 = imgui.Vec2;

const Self = @This();

const log = std.log.scoped(.AssetDB);

pub const TextureId = usize;
pub const TextureAsset = struct {
    image: Image,
    image_view: vk.ImageView,
    descriptor: vk.DescriptorSet,

    pub fn deinit(self: *const @This(), gc: *GraphicsContext) void {
        gc.vkd.destroyImageView(gc.dev, self.image_view, null);
        self.image.deinit(gc);
    }
};

const Buffer = struct {
    buffer: vk.Buffer,
    memory: vk.DeviceMemory,
    size: vk.DeviceSize,

    pub fn deinit(self: *const @This(), gc: *const GraphicsContext) void {
        gc.vkd.destroyBuffer(gc.dev, self.buffer, null);
        gc.vkd.freeMemory(gc.dev, self.memory, null);
    }
};

// AssetDB
allocator: std.mem.Allocator,
textureIds: std.StringHashMap(TextureId),
textures: std.ArrayList(*TextureAsset),
gc: *GraphicsContext,
texture_descriptor_set_layout: vk.DescriptorSetLayout,

pub fn init(allocator: std.mem.Allocator, gc: *GraphicsContext) !Self {
    const binding = vk.DescriptorSetLayoutBinding{
        .binding = 1,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .stage_flags = .{ .fragment_bit = true },
        .p_immutable_samplers = null,
    };

    const texture_descriptor_set_layout = try gc.vkd.createDescriptorSetLayout(gc.dev, &.{
        .flags = .{},
        .binding_count = 1,
        .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, &binding),
    }, null);

    return Self{
        .allocator = allocator,
        .textureIds = std.StringHashMap(TextureId).init(allocator),
        .textures = std.ArrayList(*TextureAsset).init(allocator),
        .gc = gc,
        .texture_descriptor_set_layout = texture_descriptor_set_layout,
    };
}

pub fn deinit(self: *Self) void {
    for (self.textures.items) |asset| {
        asset.deinit(self.gc);
        self.allocator.destroy(asset);
    }
    self.textures.deinit();
    self.textureIds.deinit();

    self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, self.texture_descriptor_set_layout, null);
}

pub fn getTextureByPath(self: *Self, asset_path: [:0]const u8) !*TextureAsset {
    _ = self;
    _ = asset_path;
    return error.uiae;
    // log.info("getTextureByPath({s})", .{asset_path});

    // if (self.textureIds.get(asset_path)) |id| {
    //     if (id >= self.textures.items.len)
    //         return error.InvalidTextureIdInMap;
    //     return self.textures.items[id];
    // }

    // log.debug("texture not loaded yet", .{});

    // var width: c_int = -1;
    // var height: c_int = -1;
    // var channels: c_int = -1;
    // const pixels = stb.stbi_load(asset_path.ptr, &width, &height, &channels, stb.STBI_rgb_alpha);
    // defer stb.stbi_image_free(pixels);
    // if (pixels != null) {
    //     const image_size = @intCast(u64, width) * @intCast(u64, height) * 4;
    //     log.debug("loaded texture with size {}x{} and {} channels, {} bytes", .{ width, height, channels, image_size });

    //     var buffer = try self.gc.createBuffer(image_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    //     defer buffer.deinit(self.gc);

    //     try self.gc.uploadBufferData(buffer, pixels[0..image_size]);

    //     const format = .b8g8r8a8_srgb;
    //     const image = try self.gc.createImage(@intCast(u32, width), @intCast(u32, height), .b8g8r8a8_srgb, .optimal, .{ .sampled_bit = true, .transfer_dst_bit = true }, .{ .device_local_bit = true });
    //     errdefer image.deinit(self.gc);

    //     try self.gc.transitionImageToLayout(image, format, .@"undefined", .transfer_dst_optimal);
    //     try self.gc.copyBufferToImage(buffer, image, @intCast(u32, width), @intCast(u32, height));
    //     try self.gc.transitionImageToLayout(image, format, .transfer_dst_optimal, .shader_read_only_optimal);

    //     const image_view = try self.gc.vkd.createImageView(self.gc.dev, &.{
    //         .flags = .{},
    //         .image = image.image,
    //         .view_type = .@"2d",
    //         .format = format,
    //         .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
    //         .subresource_range = .{
    //             .aspect_mask = .{ .color_bit = true },
    //             .base_mip_level = 0,
    //             .level_count = 1,
    //             .base_array_layer = 0,
    //             .layer_count = 1,
    //         },
    //     }, null);
    //     errdefer self.gc.vkd.destroyImageView(self.gc.dev, image_view, null);

    //     // creat descriptor set
    //     var descriptor: vk.DescriptorSet = .null_handle;
    //     try self.gc.vkd.allocateDescriptorSets(self.gc.dev, &.{
    //         .descriptor_pool = self.descriptor_pool,
    //         .descriptor_set_count = 1,
    //         .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &self.texture_descriptor_set_layout),
    //     }, @ptrCast([*]vk.DescriptorSet, &descriptor));
    //     std.log.debug("getTexture({x})", .{descriptor});

    //     const desc = vk.DescriptorImageInfo{
    //         .sampler = .null_handle,
    //         .image_view = image_view,
    //         .image_layout = .shader_read_only_optimal, // from last transitionImageToLayout
    //     };

    //     var write_desc: vk.WriteDescriptorSet = undefined;
    //     std.mem.set(u8, std.mem.asBytes(&write_desc), 0);
    //     write_desc.s_type = .write_descriptor_set;
    //     write_desc.dst_set = descriptor;
    //     write_desc.dst_binding = 1;
    //     write_desc.dst_array_element = 0;
    //     write_desc.descriptor_count = 1;
    //     write_desc.descriptor_type = .combined_image_sampler;
    //     write_desc.p_image_info = @ptrCast([*]const vk.DescriptorImageInfo, &desc);

    //     self.gc.vkd.updateDescriptorSets(self.gc.dev, 1, @ptrCast([*]const vk.WriteDescriptorSet, &write_desc), 0, undefined);

    //     // store asset
    //     var asset = try self.allocator.create(TextureAsset);
    //     errdefer self.allocator.destroy(asset);

    //     asset.* = TextureAsset{
    //         .image = image,
    //         .image_view = image_view,
    //         .descriptor = descriptor,
    //     };
    //     const id = self.textures.items.len;
    //     try self.textures.append(asset);
    //     errdefer _ = self.textures.pop();
    //     try self.textureIds.put(asset_path, id);

    //     return asset;
    // } else {
    //     log.err("AssetDB.getTexture({s}): Failed to load file", .{asset_path});
    //     return error.FailedToLoadFile;
    // }
}

pub fn getTextureById(self: *Self, id: TextureId) !*TextureAsset {
    if (id >= self.textures.items.len)
        return error.InvalidTextureIdInMap;
    return self.textures.items[id];
}
