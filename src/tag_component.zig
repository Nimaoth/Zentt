const std = @import("std");

pub const Tag = struct {
    name: []const u8,

    pub fn format(self: *const @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "Tag{{ {s} }}", .{self.name});
    }
};
