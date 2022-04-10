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

pub const BibleResource = struct {
    entity_ids: std.ArrayList(EntityId),
    world: *World,

    pub fn init(allocator: std.mem.Allocator, world: *World) @This() {
        return @This(){
            .entity_ids = std.ArrayList(EntityId).init(allocator),
            .world = world,
        };
    }

    pub fn deinit(self: *const @This()) void {
        self.entity_ids.deinit();
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

pub const BibleComponent = struct {
    age: f32 = 0,
};

pub fn createBible(commands: *Commands, assetdb: *AssetDB, bible_res: *BibleResource) !void {
    _ = bible_res;
    var entity = .{
        .axe = BibleComponent{},
        .transform = TransformComponent{},
        .physics = PhysicsComponent{ .own_layer = 0b0100, .target_layer = 0b0010, .radius = 7, .push_factor = 0, .inverse_mass = 99999 },
        .health = HealthComponent{},
        .sprite = SpriteComponent{ .texture = undefined },
    };
    entity.sprite.texture = try assetdb.getTextureByPath("HolyBook.png", .{});
    _ = try commands.createEntityBundle(&entity);
}

pub fn bibleSystem(
    time: *const Time,
    commands: *Commands,
    assetdb: *AssetDB,
    bible_res: *BibleResource,
    player_query: Query(.{ Player, TransformComponent }),
    query: Query(.{ BibleComponent, TransformComponent, PhysicsComponent }),
) !void {
    const player = player_query.iter().next() orelse {
        std.log.err("bibleSystem: No player found.", .{});
        return;
    };

    const base_range = imgui2.variable(bibleSystem, f32, "Bible base range", 75, true, .{ .min = 5 }).*;
    const range = base_range * player.player.area_modifier;

    const base_max_age = imgui2.variable(bibleSystem, f32, "Bible max age", 3000, true, .{ .min = 1 }).*;
    const max_age = base_max_age * player.player.duration_modifier;

    const base_cooldown = imgui2.variable(bibleSystem, f32, "Bible cooldown", 5, true, .{ .min = 1 }).*;
    const cooldown = base_cooldown * player.player.cooldown_modifier;

    const base_amount = imgui2.variable(bibleSystem, i32, "Bible amount", 2, true, .{ .min = 1 }).*;
    const amount = base_amount + player.player.amount_modifier;

    const base_speed = imgui2.variable(bibleSystem, f32, "Bible speed", 50, true, .{ .min = 1 }).*;
    const speed = base_speed * player.player.speed_modifier;

    const base_damage = imgui2.variable(bibleSystem, f32, "Bible damage", 0.5, true, .{ .min = 0, .speed = 0.1 }).*;
    const damage = base_damage * player.player.damage_modifier;

    const push_amount = imgui2.variable(bibleSystem, f32, "Bible push amount", 100, true, .{ .min = 0, .speed = 0.1 }).*;

    var last_spawn_time = imgui2.variable(bibleSystem, f32, "last_spawn_time", 0, false, .{ .min = 5 });

    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    const bible_count = query.count();

    var iter = query.iter();
    var i: u64 = 0;
    while (iter.next()) |entity| {
        const a = @intToFloat(f32, i) / @intToFloat(f32, bible_count);
        const angle = math.toRadians(speed * entity.bible.age) + a * std.math.tau;
        const offset = Vec3.new(@cos(angle), -@sin(angle), 0);
        entity.transform.position = player.transform.position.add(offset.scale(range));

        const slope = 4;
        entity.transform.size = std.math.min(entity.bible.age * slope, std.math.min(slope * max_age - slope * entity.bible.age, 1));

        entity.bible.age += delta;

        i += 1;

        if (entity.bible.age > max_age) {
            try commands.destroyEntity(entity.ref.*);
            try bible_res.returnEntityId(entity.ref.id);
        }

        for (entity.physics.colliding_entities_new) |e| {
            if (entity.physics.startedCollidingWith(e)) {
                if (bible_res.world.getComponent(e, HealthComponent) catch continue) |health| {
                    health.health -= damage;
                }
            }

            if (bible_res.world.getComponent(e, TransformComponent) catch continue) |t| {
                t.position = t.position.add(offset.scale(push_amount * delta));
            }
        }
    }

    // Spawn new bibles.
    if (bible_count == 0 and (@floatCast(f32, time.now) - last_spawn_time.*) > cooldown) {
        last_spawn_time.* = @floatCast(f32, time.now);
        var k: i32 = 0;
        while (k < amount) : (k += 1) {
            try createBible(commands, assetdb, bible_res);
        }
    }
}
