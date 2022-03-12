const std = @import("std");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const EntityId = @import("../ecs/entity.zig").EntityId;
const World = @import("../ecs/world.zig");

const AssetDB = @import("../rendering/assetdb.zig");

pub const Time = struct {
    delta: f64 = 0,
    now: f64 = 0,
};

pub const Input = struct {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
};

pub const CameraComponent = struct {
    size: f32,
};

pub const SpeedComponent = struct {
    speed: f32,
};

pub const TransformComponent = struct {
    position: Vec3 = Vec3.new(0, 0, 0),
    rotation: f32 = 0,
    size: f32 = 1,
};

pub const SpriteComponent = struct {
    texture: *AssetDB.TextureAsset,
    tiling: Vec2 = Vec2.new(1, 1),
};

pub const AnimatedSpriteComponent = struct {
    anim: *AssetDB.SpriteAnimationAsset,
    time: f32 = 0,

    pub fn getCurrentTextureIndex(self: *const @This()) usize {
        return @floatToInt(usize, (self.time / self.anim.length) * @intToFloat(f32, self.anim.sprites.len));
    }

    pub fn getCurrentTexture(self: *const @This()) *AssetDB.TextureAsset {
        return self.anim.sprites[self.getCurrentTextureIndex()];
    }
};

pub const FollowPlayerMovementComponent = struct {};
