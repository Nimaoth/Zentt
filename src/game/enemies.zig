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
const HealthComponent = basic_components.HealthComponent;
const Player = @import("player.zig").Player;
const PhysicsComponent = @import("physics.zig").PhysicsComponent;
const Gem = @import("gem.zig");

pub fn createDyingBat(commands: *Commands, assetdb: *AssetDB, pos: Vec3) !void {
    _ = (try commands.createEntity())
        .addComponent(TransformComponent{ .position = pos })
        .addComponent(AnimatedSpriteComponent{ .anim = assetdb.getSpriteAnimation("Bat1") orelse unreachable, .destroy_at_end = true });
}
pub fn createBat(commands: *Commands, assetdb: *AssetDB, pos: Vec3, health: f32) !void {
    // _ = (try commands.createEntity())
    //     .addComponent(FollowPlayerMovementComponent{})
    //     .addComponent(TransformComponent{ .position = pos })
    //     .addComponent(SpeedComponent{ .speed = 50 })
    //     .addComponent(PhysicsComponent{ .own_layer = 0b0010, .target_layer = 0b0111, .radius = 10 })
    //     .addComponent(HealthComponent{ .health = health })
    //     .addComponent(AnimatedSpriteComponent{ .anim = assetdb.getSpriteAnimation("Bat1i") orelse unreachable });
    var entity = .{
        .follow = FollowPlayerMovementComponent{},
        .transform = TransformComponent{},
        .speed = SpeedComponent{ .speed = 50 },
        .physics = PhysicsComponent{ .own_layer = 0b0010, .target_layer = 0b0111, .radius = 10 },
        .health = HealthComponent{},
        .sprite = AnimatedSpriteComponent{ .anim = undefined },
    };
    entity.transform.position = pos;
    entity.health.health = health;
    entity.sprite.anim = assetdb.getSpriteAnimation("Bat1i") orelse unreachable;
    _ = try commands.createEntityBundle(&entity);
}

pub fn moveSystemFollowPlayer(
    time: *const Time,
    spawner: *EnemySpawner,
    commands: *Commands,
    assetdb: *AssetDB,
    players: Query(.{ Player, TransformComponent }),
    query: Query(.{ FollowPlayerMovementComponent, TransformComponent, SpeedComponent, HealthComponent }),
    gems: Query(.{ Gem.GemComponent, TransformComponent }),
) !void {
    const scope = Profiler.beginScope("moveSystemFollowPlayer");
    defer scope.end();

    const max_despawn_distance = imgui2.variable(moveSystemFollowPlayer, f32, "Max despawn distance", 2000, true, .{ .min = 0 }).*;
    const max_despawn_distance_sq = max_despawn_distance * max_despawn_distance;

    const max_gem_count = imgui2.variable(moveSystemFollowPlayer, u64, "Max gem count.", 100, true, .{ .min = 0 }).*;

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
        if (entity.health.health <= 0 or distance > max_despawn_distance_sq) {
            try commands.destroyEntity(entity.ref.*);
            try createDyingBat(commands, assetdb, entity.transform.position);
            try spawner.gems_to_spawn.append(.{ .position = entity.transform.position, .xp = 1 });
            spawner.current_count -= 1;
        }
    }

    const current_gems = gems.count();
    if (current_gems < max_gem_count) {
        const max_gems_to_spawn = max_gem_count - gems.count();
        for (spawner.gems_to_spawn.items[0..std.math.min(spawner.gems_to_spawn.items.len, max_gems_to_spawn)]) |*gts| {
            try Gem.createGem(commands, assetdb, gts.position, gts.xp);
        }
    }
    spawner.gems_to_spawn.clearRetainingCapacity();
}

pub const GemToSpawn = struct {
    position: Vec3,
    xp: f32,
};

pub const EnemySpawner = struct {
    current_count: u64 = 0,
    world: *World,
    prng: std.rand.DefaultPrng,
    gems_to_spawn: std.ArrayList(GemToSpawn),

    pub fn init(allocator: std.mem.Allocator, world: *World) @This() {
        _ = allocator;
        return @This(){
            .world = world,
            .prng = std.rand.DefaultPrng.init(123),
            .gems_to_spawn = std.ArrayList(GemToSpawn).init(allocator),
        };
    }

    pub fn deinit(self: *const @This()) void {
        self.gems_to_spawn.deinit();
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

    const min_spawn_distance = imgui2.variable(enemySpawnSystem, f32, "Spawn distance", 200, true, .{ .min = 0 }).*;
    const spawn_distance_width = imgui2.variable(enemySpawnSystem, f32, "Spawn distance width", 200, true, .{ .min = 0 }).*;
    const max_spawn_distance = min_spawn_distance + spawn_distance_width;

    const desired_count = imgui2.variable(enemySpawnSystem, i32, "Desired enemies", 10, true, .{ .min = 0 }).*;
    const base_health = imgui2.variable(enemySpawnSystem, f32, "Bat health", 10, true, .{ .min = 0, .speed = 0.1 }).*;
    const health = base_health;

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var rand = spawner.rand();

    while (spawner.current_count < desired_count) {
        const angle = rand.float(f32) * std.math.tau;
        const offset = Vec3.new(@cos(angle), -@sin(angle), 0);
        const distance = math.lerp(f32, min_spawn_distance, max_spawn_distance, rand.float(f32));
        const position = player.transform.position.add(offset.scale(distance));
        try createBat(commands, assetdb, position, health);
        spawner.current_count += 1;
    }
}
