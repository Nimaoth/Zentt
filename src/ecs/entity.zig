const std = @import("std");
const Chunk = @import("chunk.zig");

pub const EntityId = u64;
pub const ComponentId = u64;

id: u64,
chunk: *Chunk,
index: u64,

const Self = @This();

pub fn format(self: *const @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "<{} : {}>", .{ self.index, self.chunk.table.archetype });
}
