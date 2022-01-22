const std = @import("std");

hash: u64,
name: []const u8,
size: u32,
alignment: u32,

const Self = @This();

pub fn init(comptime T: type) Self {
    _ = T;
    const hash = std.hash.Wyhash.hash(69, @typeName(T));
    return Self{
        .hash = hash,
        .name = @typeName(T),
        .size = @sizeOf(T),
        .alignment = @alignOf(T),
    };
}

pub const Context = struct {
    pub fn hash(context: @This(), self: Self) u64 {
        _ = context;
        return self.hash;
    }
    pub fn eql(context: @This(), a: Self, b: Self) bool {
        _ = context;

        if (a.hash != b.hash) {
            return false;
        }

        return std.mem.eql(u8, a.name, b.name);
    }
};

pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "{s}", .{self.name});
}
