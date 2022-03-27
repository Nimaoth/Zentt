const std = @import("std");

const imgui2 = @import("../editor/imgui2.zig");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;

const Renderer = @import("../rendering/renderer.zig");
const SpriteRenderer = @import("../rendering/sprite_renderer.zig");
const AssetDB = @import("../rendering/assetdb.zig");

const Profiler = @import("../editor/profiler.zig");

const EntityId = @import("/../ecs/entity.zig").EntityId;
const World = @import("../ecs/world.zig");
const Query = @import("../ecs/query.zig").Query;
const Commands = @import("../ecs/commands.zig");

const basic_components = @import("basic_components.zig");
const Time = basic_components.Time;
const TransformComponent = basic_components.TransformComponent;
const SpeedComponent = basic_components.SpeedComponent;
const SpriteComponent = basic_components.SpriteComponent;
const AnimatedSpriteComponent = basic_components.AnimatedSpriteComponent;
const HealthComponent = basic_components.HealthComponent;
const Player = @import("player.zig").Player;

pub const GemComponent = struct {
    follow_player: bool = false,
    xp: f32 = 0,
};

pub fn createGem(commands: *Commands, assetdb: *AssetDB, position: Vec3, xp: f32) !void {
    _ = (try commands.createEntity())
        .addComponent(GemComponent{ .xp = xp })
        .addComponent(TransformComponent{ .position = position })
        .addComponent(SpriteComponent{ .texture = try assetdb.getTextureByPath("Gem1.png", .{}) });
}

pub fn gemSystem(
    time: *const Time,
    commands: *Commands,
    player_query: Query(.{ Player, TransformComponent }),
    query: Query(.{ GemComponent, TransformComponent }),
) !void {
    const player = player_query.iter().next() orelse {
        std.log.err("gemSystem: No player found.", .{});
        return;
    };

    const base_attract_distance = imgui2.variable(gemSystem, f32, "Gem attract area", 100, true, .{ .min = 1, .speed = 0.1 }).*;
    const attract_distance = base_attract_distance * player.player.attract_range_modifier;

    const gem_radius = imgui2.variable(gemSystem, f32, "Gem radius", 20, true, .{ .min = 1, .speed = 0.1 }).*;

    const base_xp_modifier = imgui2.variable(gemSystem, f32, "Gem xp multiplier", 1, true, .{ .min = 0.1 }).*;
    const xp_modifier = base_xp_modifier * player.player.xp_modifier;

    const gem_speed = imgui2.variable(gemSystem, f32, "Gem speed", 350, true, .{ .min = 0.1 }).*;

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    const attract_distance_sq = attract_distance * attract_distance;
    const gem_radius_sq = gem_radius * gem_radius;

    var iter = query.iter();
    while (iter.next()) |entity| {
        const to_player = player.transform.position.sub(entity.transform.position);
        const distance = to_player.lengthSq();
        if (distance <= attract_distance_sq) {
            entity.gem.follow_player = true;
        }
        if (distance < gem_radius_sq) {
            player.player.xp += entity.gem.xp * xp_modifier;
            _ = try commands.destroyEntity(entity.ref);
        }

        if (entity.gem.follow_player) {
            const vel = to_player.norm().scale(gem_speed);
            entity.transform.position = entity.transform.position.add(vel.scale(delta));
        }
    }
}
