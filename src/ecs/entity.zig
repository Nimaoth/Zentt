const std = @import("std");
const Chunk = @import("chunk.zig");

pub const EntityId = u64;
pub const ComponentId = u64;

const Self = @This();

pub const Ref = struct {
    id: EntityId = 0,
    entity: *Self = undefined,

    pub fn get(self: *const @This()) ?*Self {
        if (self.isValid()) {
            return self.entity;
        } else {
            return null;
        }
    }

    pub fn isValid(self: *const @This()) bool {
        return self.id != 0 and self.id == self.entity.id;
    }
};

id: u64 = 0,
chunk: *Chunk = undefined,
index: u64 = 0,

pub fn format(self: *const @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "<{} : {}>", .{ self.index, self.chunk.table.archetype });
}
