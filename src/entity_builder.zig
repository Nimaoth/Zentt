const std = @import("std");

const Entity = @import("entity.zig");
const World = @import("world.zig");

const Self = @This();

world: *World,
entity: ?Entity,
err: std.meta.Int(.unsigned, @sizeOf(anyerror) * 8),

const Tag = struct {
    name: []const u8,

    pub fn format(self: *const @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(self.name);
    }
};

pub fn init(world: *World, name: []const u8) Self {
    var errCode: std.meta.Int(.unsigned, @sizeOf(anyerror) * 8) = 0;
    var entity = world.createEntity(name) catch |err| blk: {
        errCode = @errorToInt(err);
        break :blk null;
    };

    var builder = Self{
        .world = world,
        .entity = entity,
        .err = errCode,
    };

    return builder;
    // return builder.addComponent(Tag{ .name = name }).*;
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
