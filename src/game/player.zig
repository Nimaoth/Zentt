const std = @import("std");

const imgui = @import("../editor/imgui.zig");
const imgui2 = @import("../editor/imgui2.zig");

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Profiler = @import("../editor/profiler.zig");

const EntityId = @import("../ecs/entity.zig").EntityId;
const World = @import("../ecs/world.zig");
const Query = @import("../ecs/query.zig").Query;
const Commands = @import("../ecs/commands.zig");

const basic_components = @import("basic_components.zig");
const Time = basic_components.Time;
const Input = basic_components.Input;
const TransformComponent = basic_components.TransformComponent;
const SpeedComponent = basic_components.SpeedComponent;

const physics = @import("physics.zig");
const PhysicsComponent = physics.PhysicsComponent;

pub const Player = struct {
    area_modifier: f32 = 1,
    speed_modifier: f32 = 1,
    duration_modifier: f32 = 1,
    damage_modifier: f32 = 1,
    cooldown_modifier: f32 = 1,
    amount_modifier: i32 = 0,
    xp_modifier: f32 = 1,
    attract_range_modifier: f32 = 1,

    level: u64 = 0,
    xp: f32 = 0,
    next_level_xp: f32 = 100,

    velocity: Vec3 = Vec3.zero(),
};

pub fn moveSystemPlayer(
    time: *const Time,
    input: *const Input,
    query: Query(.{ Player, TransformComponent, SpeedComponent, PhysicsComponent }),
) !void {
    const delta = @floatCast(f32, time.delta);
    if (delta == 0)
        return;

    var iter = query.iter();
    while (iter.next()) |entity| {
        var dir = Vec3.zero();
        if (input.left) dir = dir.add(Vec3.new(-1, 0, 0));
        if (input.right) dir = dir.add(Vec3.new(1, 0, 0));
        if (input.up) dir = dir.add(Vec3.new(0, 1, 0));
        if (input.down) dir = dir.add(Vec3.new(0, -1, 0));

        const vel = dir.norm().scale(entity.speed.speed);
        entity.player.velocity = vel;
        entity.transform.position = entity.transform.position.add(vel.scale(delta));

        if (entity.player.xp >= entity.player.next_level_xp) {
            entity.player.xp -= entity.player.next_level_xp;
            entity.player.next_level_xp *= 1.15;
            entity.player.level += 1;
        }

        // for (entity.physics.colliding_entities_new) |e| {
        //     if (entity.physics.startedCollidingWith(e)) {
        //         std.log.debug("Collided begin {}", .{e});
        //     }
        // }
        // for (entity.physics.colliding_entities_old) |e| {
        //     if (entity.physics.stoppedCollidingWith(e)) {
        //         std.log.debug("Collided end   {}", .{e});
        //     }
        // }
    }
}
