const std = @import("std");

hash: u64,
name: []const u8,
id: u64,
size: u32,
alignment: u32,

const Self = @This();

fn typeId(comptime T: type) usize {
    _ = T;
    return @ptrToInt(&struct {
        var x: u8 = 0;
    }.x);
}

pub fn init(comptime T: type) Self {
    const hash = std.hash.Wyhash.hash(69, @typeName(T));
    return Self{
        .hash = hash,
        .name = @typeName(T),
        .id = typeId(T),
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

        return a.id == b.id;
    }
};

pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "{s}@{}", .{ self.name, self.id });
}
