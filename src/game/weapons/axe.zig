const std = @import("std");

const imgui2 = @import("../../editor/imgui2.zig");

const math = @import("../../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;

const Renderer = @import("../../rendering/renderer.zig");
const SpriteRenderer = @import("../../rendering/sprite_renderer.zig");
const AssetDB = @import("../../rendering/assetdb.zig");

const Profiler = @import("../../editor/profiler.zig");

const EntityId = @import("../../ecs/entity.zig").EntityId;
const World = @import("../../ecs/world.zig");
const Query = @import("../../ecs/query.zig").Query;
const Commands = @import("../../ecs/commands.zig");

const basic_components = @import("../basic_components.zig");
const Time = basic_components.Time;
const TransformComponent = basic_components.TransformComponent;
const SpeedComponent = basic_components.SpeedComponent;
const SpriteComponent = basic_components.SpriteComponent;
const Player = @import("../player.zig").Player;
const PhysicsComponent = @import("../physics.zig").PhysicsComponent;
const HealthComponent = basic_components.HealthComponent;

pub const AxeResource = struct {
    entity_ids: std.ArrayList(EntityId),
    world: *World,
    prng: std.rand.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, world: *World) @This() {
        return @This(){
            .entity_ids = std.ArrayList(EntityId).init(allocator),
            .world = world,
            .prng = std.rand.DefaultPrng.init(123),
        };
    }

    pub fn deinit(self: *const @This()) void {
        self.entity_ids.deinit();
    }

    pub fn rand(self: *@This()) std.rand.Random {
        return self.prng.random();
    }

    pub fn getFreeEntityId(self: *@This()) EntityId {
        if (self.entity_ids.items.len > 0) {
            return self.entity_ids.pop();
        } else {
            return self.world.reserveEntityId();
        }
    }

    pub fn returnEntityId(self: *@This(), entity_id: EntityId) !void {
        try self.entity_ids.append(entity_id);
    }
};

pub const AxeComponent = struct {
    age: f32 = 0,
    velocity: Vec3 = Vec3.zero(),
};

pub fn createAxe(commands: *Commands, assetdb: *AssetDB, axe_res: *AxeResource, position: Vec3, velocity: Vec3) !void {
    _ = (try commands.createEntityWithId(axe_res.getFreeEntityId()))
        .addComponent(AxeComponent{ .velocity = velocity })
        .addComponent(TransformComponent{ .position = position })
        .addComponent(PhysicsComponent{ .own_layer = 0b0100, .target_layer = 0b0010, .radius = 10, .push_factor = 0, .inverse_mass = 10000 })
        .addComponent(SpriteComponent{ .texture = try assetdb.getTextureByPath("Axe.png", .{}) });
}

pub fn axeSystem(
    time: *const Time,
    commands: *Commands,
    assetdb: *AssetDB,
    axe_res: *AxeResource,
    player_query: Query(.{ Player, TransformComponent }),
    query: Query(.{ AxeComponent, TransformComponent, PhysicsComponent }),
) !void {
    const player = player_query.iter().next() orelse {
        std.log.err("axeSystem: No player found.", .{});
        return;
    };

    const base_area = imgui2.variable(axeSystem, f32, "Axe base area", 1, true, .{ .min = 1, .speed = 0.1 }).*;
    const area = base_area * player.player.area_modifier;

    const base_max_age = imgui2.variable(axeSystem, f32, "Axe max age", 3, false, .{ .min = 1, .speed = 0.1 }).*;
    const max_age = base_max_age * player.player.duration_modifier;

    const base_cooldown = imgui2.variable(axeSystem, f32, "Axe cooldown", 3, true, .{ .min = 0.1 }).*;
    const cooldown = base_cooldown * player.player.cooldown_modifier;

    const base_amount = imgui2.variable(axeSystem, i32, "Axe amount", 2, true, .{ .min = 1 }).*;
    const amount = base_amount + player.player.amount_modifier;

    const base_speed = imgui2.variable(axeSystem, f32, "Axe speed", 200, true, .{ .min = 1 }).*;
    const speed = base_speed * player.player.speed_modifier;

    const base_damage = imgui2.variable(axeSystem, f32, "Axe damage", 11, true, .{ .min = 0, .speed = 0.1 }).*;
    const damage = base_damage * player.player.damage_modifier;

    var last_spawn_time = imgui2.variable(axeSystem, f32, "last_spawn_time", 0, false, .{ .min = 5 });

    var gravity = imgui2.variable(axeSystem, f32, "Ave gravity", -300, true, .{ .speed = 0.1 }).*;
    var rotation_speed = imgui2.variable(axeSystem, f32, "Axe rotation speed", 360, true, .{ .speed = 0.1 }).*;
    var dir_stddev = imgui2.variable(axeSystem, f32, "Axe direction deviation", 0.2, true, .{ .speed = 0.1 }).*;
    var player_velocity_factor = imgui2.variable(axeSystem, f32, "Axe player velocity factor", 0.4, true, .{ .speed = 0.1 }).*;

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var iter = query.iter();
    while (iter.next()) |entity| {
        entity.axe.velocity = entity.axe.velocity.add(Vec3.new(0, gravity * delta, 0));
        entity.transform.position = entity.transform.position.add(entity.axe.velocity.scale(delta));

        entity.transform.rotation += rotation_speed * delta;

        const slope = 8;
        entity.transform.size = std.math.min(entity.axe.age * slope, std.math.min(slope * max_age - slope * entity.axe.age, area * 1.5));
        entity.axe.age += delta;

        if (entity.axe.age > max_age) {
            try commands.destroyEntity(entity.id);
            try axe_res.returnEntityId(entity.id);
        }

        for (entity.physics.colliding_entities_new) |e| {
            if (entity.physics.startedCollidingWith(e)) {
                if (axe_res.world.getComponent(e, HealthComponent) catch continue) |health| {
                    health.health -= damage;
                }
            }
        }
    }

    // Spawn new axes.
    if ((@floatCast(f32, time.now) - last_spawn_time.*) > cooldown) {
        last_spawn_time.* = @floatCast(f32, time.now);

        var rand = axe_res.rand();

        var k: i32 = 0;
        while (k < amount) : (k += 1) {
            const velocity = Vec3.new(rand.floatNorm(f32) * dir_stddev, 1, 0).norm().scale(speed).add(player.player.velocity.scale(player_velocity_factor));
            try createAxe(commands, assetdb, axe_res, player.transform.position, velocity);
        }
    }
}
