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

const EntityId = @import("../ecs/entity.zig").EntityId;
const World = @import("../ecs/world.zig");
const Query = @import("../ecs/query.zig").Query;
const Commands = @import("../ecs/commands.zig");

const basic_components = @import("basic_components.zig");
const Time = basic_components.Time;
const TransformComponent = basic_components.TransformComponent;
const SpeedComponent = basic_components.SpeedComponent;
const SpriteComponent = basic_components.SpriteComponent;
const AnimatedSpriteComponent = basic_components.AnimatedSpriteComponent;
const FollowPlayerMovementComponent = basic_components.FollowPlayerMovementComponent;
const CameraComponent = basic_components.CameraComponent;
const Player = @import("player.zig").Player;
const PhysicsComponent = @import("physics.zig").PhysicsComponent;

pub fn createBat(commands: *Commands, assetdb: *AssetDB, pos: Vec3) !void {
    _ = (try commands.createEntity())
        .addComponent(FollowPlayerMovementComponent{})
        .addComponent(TransformComponent{ .position = pos })
        .addComponent(SpeedComponent{ .speed = 25 })
        .addComponent(PhysicsComponent{ .layer = 2, .radius = 10 })
        .addComponent(AnimatedSpriteComponent{ .anim = assetdb.getSpriteAnimation("Bat1i") orelse unreachable });
}

pub fn moveSystemFollowPlayer(
    profiler: *Profiler,
    time: *const Time,
    spawner: *EnemySpawner,
    commands: *Commands,
    players: Query(.{ Player, TransformComponent }),
    query: Query(.{ FollowPlayerMovementComponent, TransformComponent, SpeedComponent }),
) !void {
    const scope = profiler.beginScope("moveSystemFollowPlayer");
    defer scope.end();

    const min_despawn_distance = imgui2.variable(moveSystemFollowPlayer, f32, "Min despawn distance", 0, true, .{ .min = 0 }).*;
    const max_despawn_distance = imgui2.variable(moveSystemFollowPlayer, f32, "Max despawn distance", 2000, true, .{ .min = 0 }).*;
    const min_despawn_distance_sq = min_despawn_distance * min_despawn_distance;
    const max_despawn_distance_sq = max_despawn_distance * max_despawn_distance;

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var player = players.iter().next() orelse {
        std.log.warn("moveSystemFollowPlayer: Player not found", .{});
        return;
    };

    var iter = query.iter();
    while (iter.next()) |entity| {
        const toPlayer = player.transform.position.sub(entity.transform.position).mul(Vec3.new(1, 1, 0));
        const vel = toPlayer.norm().scale(entity.speed.speed);
        entity.transform.position = entity.transform.position.add(vel.scale(delta));

        const distance = toPlayer.lengthSq();
        if (distance < min_despawn_distance_sq or distance > max_despawn_distance_sq) {
            try commands.destroyEntity(entity.id);
            spawner.current_count -= 1;
        }
    }
}

pub const EnemySpawner = struct {
    current_count: u64 = 0,
    world: *World,
    prng: std.rand.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, world: *World) @This() {
        _ = allocator;
        return @This(){
            .world = world,
            .prng = std.rand.DefaultPrng.init(123),
        };
    }

    pub fn deinit(self: *const @This()) void {
        _ = self;
    }

    pub fn rand(self: *@This()) std.rand.Random {
        return self.prng.random();
    }
};

pub fn enemySpawnSystem(
    time: *const Time,
    spawner: *EnemySpawner,
    commands: *Commands,
    assetdb: *AssetDB,
    players: Query(.{ Player, TransformComponent, CameraComponent }),
) !void {
    var player = players.iter().next() orelse {
        std.log.warn("moveSystemFollowPlayer: Player not found", .{});
        return;
    };

    const distance_modifier = imgui2.variable(enemySpawnSystem, f32, "Spawn distance", 500, true, .{ .min = 0 }).*;
    // var min_distance_from_player = player.camera.size * distance_modifier;
    var min_distance_from_player = distance_modifier;
    var max_distance_from_player = min_distance_from_player + 100;

    const desired_count = imgui2.variable(enemySpawnSystem, i32, "Desired enemies", 0, true, .{ .min = 0 }).*;

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var rand = spawner.rand();

    while (spawner.current_count < desired_count) {
        const angle = rand.float(f32) * std.math.tau;
        const offset = Vec3.new(@cos(angle), -@sin(angle), 0);
        const distance = math.lerp(f32, min_distance_from_player, max_distance_from_player, rand.float(f32));
        const position = player.transform.position.add(offset.scale(distance));
        try createBat(commands, assetdb, position);
        spawner.current_count += 1;
    }
}
