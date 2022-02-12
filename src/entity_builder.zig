const std = @import("std");

const Entity = @import("entity.zig");
const World = @import("world.zig");
const Tag = @import("tag_component.zig").Tag;

const Self = @This();

world: *World,
entity: ?Entity,
err: std.meta.Int(.unsigned, @sizeOf(anyerror) * 8),

pub fn init(world: *World) Self {
    var errCode: std.meta.Int(.unsigned, @sizeOf(anyerror) * 8) = 0;
    var entity = world.createEntity() catch |err| blk: {
        errCode = @errorToInt(err);
        break :blk null;
    };

    var builder = Self{
        .world = world,
        .entity = entity,
        .err = errCode,
    };

    return builder;
}

pub fn initWithTag(world: *World, name: []const u8) Self {
    return init(world).addComponent(Tag{ .name = name }).*;
}

pub fn addComponent(self: *Self, component: anytype) *Self {
    if (self.err != 0) {
        return self;
    }
    if (self.entity) |e| {
        self.entity = self.world.addComponent(e.id, component) catch |err| blk: {
            self.err = @errorToInt(err);
            break :blk null;
        };
    }

    return self;
}

pub fn build(self: *Self) !Entity {
    if (self.err != 0) {
        return @intToError(self.err);
    }
    if (self.entity) |e| {
        return e;
    } else {
        return error.NotInitialized;
    }
}
