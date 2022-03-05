const std = @import("std");

const World = @import("world.zig");
const ArchetypeTable = @import("archetype_table.zig");
const BitSet = @import("../util/bit_set.zig");

hash: u64,
components: BitSet,
world: *World,

const Self = @This();

pub fn init(world: *World, hash: u64, components: BitSet) Self {
    return Self{
        .hash = hash,
        .components = components,
        .world = world,
    };
}

pub fn clone(self: *const Self) !Self {
    return Self.init(self.world, self.hash, self.components);
}

pub fn addComponents(self: *const Self, hash: u64, components: BitSet) Self {
    var newComponents = self.components;
    newComponents.setUnion(components);
    return Self.init(self.world, self.hash ^ hash, newComponents);
}

pub fn removeComponents(self: *const Self, hash: u64, components: BitSet) Self {
    var newComponents = self.components;
    newComponents.subtract(components);
    return Self.init(self.world, self.hash ^ hash, newComponents);
}

pub const Context = struct {
    pub fn hash(context: @This(), self: *const Self) u64 {
        _ = context;
        return self.hash;
    }
    pub fn eql(context: @This(), a: *const Self, b: *Self) bool {
        _ = context;
        if (a.hash != b.hash) {
            return false;
        }

        const result = std.meta.eql(a.components, b.components);
        return result;
    }
};

pub const HashTableContext = struct {
    pub fn hash(context: @This(), self: *const Self) u64 {
        _ = context;
        return self.hash;
    }
    pub fn eql(context: @This(), a: *const Self, b: *ArchetypeTable) bool {
        _ = context;
        if (a.hash != b.archetype.hash) {
            return false;
        }

        const result = std.meta.eql(a.components, b.archetype.components);
        return result;
    }
};

pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "{{", .{});
    var iter = self.components.iterator();
    var i: u64 = 0;
    while (iter.next()) |componentId| {
        defer i += 1;
        if (i > 0) {
            try std.fmt.format(writer, ", ", .{});
        }
        const rtti = self.world.getComponentType(componentId) orelse unreachable;
        try std.fmt.format(writer, "{}", .{rtti});
    }
    try std.fmt.format(writer, "}}", .{});
}
