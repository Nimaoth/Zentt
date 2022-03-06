const std = @import("std");

const stb = @import("stb_image.zig");
const vk = @import("vulkan");
const GraphicsContext = @import("vulkan/graphics_context.zig").GraphicsContext;
const Image = @import("vulkan/graphics_context.zig").Image;
const zal = @import("zalgebra");

const Self = @This();

const log = std.log.scoped(.AssetDB);

pub const TextureId = usize;
pub const TextureAsset = struct {
    pub const ImageTexture = struct {
        image: Image,
        image_view: vk.ImageView,
        sampler: vk.Sampler,
    };

    data: union(enum) {
        image: ImageTexture,
        ref: struct {
            asset: *TextureAsset,
            uv: zal.Vec4,
            size: zal.Vec2,
        },
    },

    pub fn deinit(self: *@This(), gc: *GraphicsContext) void {
        switch (self.data) {
            .image => |image| {
                gc.vkd.destroyImageView(gc.dev, image.image_view, null);
                gc.vkd.destroySampler(gc.dev, image.sampler, null);
                image.image.deinit(gc);
            },
            else => {},
        }
    }

    pub fn resolve(self: *@This()) ImageTexture {
        switch (self.data) {
            .image => |image| {
                return image;
            },
            .ref => |ref| {
                return ref.asset.resolve();
            },
        }
    }

    pub fn getUV(self: *@This()) zal.Vec4 {
        switch (self.data) {
            .image => |_| {
                return zal.Vec4.new(0, 0, 1, 1);
            },
            .ref => |ref| {
                return ref.uv;
            },
        }
    }

    pub fn getSize(self: *@This()) zal.Vec2 {
        switch (self.data) {
            .image => |image| {
                return zal.Vec2.new(@intToFloat(f32, image.image.extent.width), @intToFloat(f32, image.image.extent.height));
            },
            .ref => |ref| {
                return ref.size;
            },
        }
    }
};
pub const TextureOptions = struct {
    filter: vk.Filter = .linear,
};

// AssetDB
allocator: std.mem.Allocator,
path_arena: std.heap.ArenaAllocator,
textureIds: std.StringHashMap(TextureId),
textures: std.ArrayList(*TextureAsset),
gc: *GraphicsContext,

pub fn init(allocator: std.mem.Allocator, gc: *GraphicsContext) !Self {
    return Self{
        .allocator = allocator,
        .path_arena = std.heap.ArenaAllocator.init(allocator),
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
    self.path_arena.deinit();
}

const TexturePackJson = struct {
    textures: []struct {
        image: []const u8,
        format: []const u8,
        size: struct {
            w: f64,
            h: f64,
        },
        scale: f64,
        frames: []struct {
            filename: []const u8,
            rotated: bool,
            trimmed: bool,
            sourceSize: struct {
                w: f64,
                h: f64,
            },
            spriteSourceSize: struct {
                x: f64,
                y: f64,
                w: f64,
                h: f64,
            },
            frame: struct {
                x: f64,
                y: f64,
                w: f64,
                h: f64,
            },
        },
    },
    meta: struct {
        app: []const u8,
        version: []const u8,
        smartupdate: []const u8,
    },
};

pub fn loadTexturePack(self: *Self, json_path: [:0]const u8, options: TextureOptions) !void {
    const json_text = try std.fs.cwd().readFileAlloc(self.allocator, json_path, std.math.maxInt(u64));
    defer self.allocator.free(json_text);
    var token_stream = std.json.TokenStream.init(json_text);
    const parse_options = std.json.ParseOptions{ .allocator = self.allocator, .ignore_unknown_fields = true, .allow_trailing_data = true };
    const texture_pack_json: TexturePackJson = try std.json.parse(TexturePackJson, &token_stream, parse_options);
    defer std.json.parseFree(TexturePackJson, texture_pack_json, parse_options);

    const folder = std.fs.path.dirname(json_path) orelse "";

    for (texture_pack_json.textures) |texture_json| {
        const texture_pack_path = try std.fs.path.join(self.allocator, &.{ folder, texture_json.image });
        defer self.allocator.free(texture_pack_path);

        var texture_pack = try self.getTextureByPath(texture_pack_path, options);
        _ = texture_pack;

        for (texture_json.frames) |*frame| {
            // store asset
            var asset = try self.allocator.create(TextureAsset);
            errdefer self.allocator.destroy(asset);

            const asset_path = try self.path_arena.allocator().dupe(u8, frame.filename);

            asset.* = TextureAsset{ .data = .{ .ref = .{
                .asset = texture_pack,
                .uv = zal.Vec4.new(
                    @floatCast(f32, frame.frame.x / texture_json.size.w),
                    @floatCast(f32, (frame.frame.y + frame.frame.h) / texture_json.size.h),
                    @floatCast(f32, (frame.frame.x + frame.frame.w) / texture_json.size.w),
                    @floatCast(f32, frame.frame.y / texture_json.size.h),
                ),
                .size = zal.Vec2.new(
                    @floatCast(f32, frame.frame.w),
                    @floatCast(f32, frame.frame.h),
                ),
            } } };
            const id = self.textures.items.len;
            try self.textures.append(asset);
            errdefer _ = self.textures.pop();
            try self.textureIds.put(asset_path, id);
        }
    }
}

pub fn getTextureByPath(self: *Self, asset_path: []const u8, options: TextureOptions) !*TextureAsset {
    if (self.textureIds.get(asset_path)) |id| {
        if (id >= self.textures.items.len)
            return error.InvalidTextureIdInMap;
        return self.textures.items[id];
    }

    log.info("Load texture from file: {s}", .{asset_path});

    var asset_path_c = std.ArrayList(u8).init(self.allocator);
    defer asset_path_c.deinit();
    try asset_path_c.appendSlice(asset_path);
    try asset_path_c.append(0);

    var width: c_int = -1;
    var height: c_int = -1;
    var channels: c_int = -1;
    const pixels = stb.stbi_load(asset_path_c.items.ptr, &width, &height, &channels, stb.STBI_rgb_alpha);
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

        try self.gc.transitionImageToLayout(image, format, .@"undefined", .transfer_dst_optimal, null);
        try self.gc.copyBufferToImage(buffer, image, @intCast(u32, width), @intCast(u32, height));
        try self.gc.transitionImageToLayout(image, format, .transfer_dst_optimal, .shader_read_only_optimal, null);

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
            .mag_filter = options.filter,
            .min_filter = options.filter,
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

        asset.* = TextureAsset{ .data = .{ .image = .{
            .image = image,
            .image_view = image_view,
            .sampler = sampler,
        } } };
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
