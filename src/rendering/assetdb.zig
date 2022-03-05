const std = @import("std");

const stb = @import("stb_image.zig");
const vk = @import("vulkan");
const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Image = @import("vulkan/graphics_context.zig").Image;

const Self = @This();

const log = std.log.scoped(.AssetDB);

pub const TextureId = usize;
pub const TextureAsset = struct {
    image: Image,
    image_view: vk.ImageView,
    sampler: vk.Sampler,

    pub fn deinit(self: *const @This(), gc: *GraphicsContext) void {
        gc.vkd.destroyImageView(gc.dev, self.image_view, null);
        gc.vkd.destroySampler(gc.dev, self.sampler, null);
        self.image.deinit(gc);
    }
};

// AssetDB
allocator: std.mem.Allocator,
textureIds: std.StringHashMap(TextureId),
textures: std.ArrayList(*TextureAsset),
gc: *GraphicsContext,

pub fn init(allocator: std.mem.Allocator, gc: *GraphicsContext) !Self {
    return Self{
        .allocator = allocator,
        .textureIds = std.StringHashMap(TextureId).init(allocator),
        .textures = std.ArrayList(*TextureAsset).init(allocator),
        .gc = gc,
    };
}

pub fn deinit(self: *Self) void {
    for (self.textures.items) |asset| {
        asset.deinit(self.gc);
        self.allocator.destroy(asset);
    }
    self.textures.deinit();
    self.textureIds.deinit();
}

pub fn getTextureByPath(self: *Self, asset_path: [:0]const u8) !*TextureAsset {
    if (self.textureIds.get(asset_path)) |id| {
        if (id >= self.textures.items.len)
            return error.InvalidTextureIdInMap;
        return self.textures.items[id];
    }

    log.info("Load texture from file: {s}", .{asset_path});

    var width: c_int = -1;
    var height: c_int = -1;
    var channels: c_int = -1;
    const pixels = stb.stbi_load(asset_path.ptr, &width, &height, &channels, stb.STBI_rgb_alpha);
    defer stb.stbi_image_free(pixels);
    if (pixels != null) {
        const image_size = @intCast(u64, width) * @intCast(u64, height) * 4;
        log.debug("loaded texture with size {}x{} and {} channels, {} bytes", .{ width, height, channels, image_size });

        var buffer = try self.gc.createBuffer(image_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
        defer buffer.deinit(self.gc);

        try self.gc.uploadBufferData(buffer, pixels[0..image_size]);

        const format = .b8g8r8a8_srgb;
        const image = try self.gc.createImage(@intCast(u32, width), @intCast(u32, height), .b8g8r8a8_srgb, .optimal, .{ .sampled_bit = true, .transfer_dst_bit = true }, .{ .device_local_bit = true });
        errdefer image.deinit(self.gc);

        try self.gc.transitionImageToLayout(image, format, .@"undefined", .transfer_dst_optimal);
        try self.gc.copyBufferToImage(buffer, image, @intCast(u32, width), @intCast(u32, height));
        try self.gc.transitionImageToLayout(image, format, .transfer_dst_optimal, .shader_read_only_optimal);

        const image_view = try self.gc.vkd.createImageView(self.gc.dev, &.{
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
        errdefer self.gc.vkd.destroyImageView(self.gc.dev, image_view, null);

        var sampler = try self.gc.vkd.createSampler(self.gc.dev, &.{
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

        // store asset
        var asset = try self.allocator.create(TextureAsset);
        errdefer self.allocator.destroy(asset);

        asset.* = TextureAsset{
            .image = image,
            .image_view = image_view,
            .sampler = sampler,
        };
        const id = self.textures.items.len;
        try self.textures.append(asset);
        errdefer _ = self.textures.pop();
        try self.textureIds.put(asset_path, id);

        return asset;
    } else {
        log.err("AssetDB.getTexture({s}): Failed to load file", .{asset_path});
        return error.FailedToLoadFile;
    }
}

pub fn getTextureById(self: *Self, id: TextureId) !*TextureAsset {
    if (id >= self.textures.items.len)
        return error.InvalidTextureIdInMap;
    return self.textures.items[id];
}
