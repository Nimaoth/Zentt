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
const Player = @import("player.zig").Player;

pub const BibleComponent = struct {
    age: f32 = 0,
};

pub fn createBible(commands: *Commands, assetdb: *AssetDB) !void {
    _ = (try commands.createEntity())
        .addComponent(BibleComponent{})
        .addComponent(TransformComponent{})
        .addComponent(SpriteComponent{ .texture = try assetdb.getTextureByPath("HolyBook.png", .{}) });
}

pub fn bibleSystem(
    time: *const Time,
    player_query: Query(.{ Player, TransformComponent }),
    query: Query(.{ BibleComponent, TransformComponent }),
    commands: *Commands,
    assetdb: *AssetDB,
    profiler: *Profiler,
) !void {
    const scope = profiler.beginScope("bibleSystem");
    defer scope.end();

    const player = player_query.iter().next() orelse {
        std.log.err("bibleSystem: No player found.", .{});
        return;
    };

    const base_range = imgui2.variable(bibleSystem, f32, "Bible base range", 100, true, .{ .min = 5 }).*;
    const range = base_range * player.player.area_modifier;

    const base_max_age = imgui2.variable(bibleSystem, f32, "Bible max age", 3, true, .{ .min = 1 }).*;
    const max_age = base_max_age * player.player.duration_modifier;

    const base_cooldown = imgui2.variable(bibleSystem, f32, "Bible cooldown", 5, true, .{ .min = 1 }).*;
    const cooldown = base_cooldown * player.player.cooldown_modifier;

    const base_amount = imgui2.variable(bibleSystem, i32, "Bible amount", 1, true, .{ .min = 1 }).*;
    const amount = base_amount + player.player.amount_modifier;

    const base_speed = imgui2.variable(bibleSystem, f32, "Bible speed", 50, true, .{ .min = 1 }).*;
    const speed = base_speed * player.player.speed_modifier;

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
            try commands.destroyEntity(entity.id);
        }
    }

    // Spawn new bibles.
    if (bible_count == 0 and (@floatCast(f32, time.now) - last_spawn_time.*) > cooldown) {
        last_spawn_time.* = @floatCast(f32, time.now);
        var k: i32 = 0;
        while (k < amount) : (k += 1) {
            try createBible(commands, assetdb);
        }
    }
}
