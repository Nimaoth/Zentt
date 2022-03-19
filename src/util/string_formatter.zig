const std = @import("std");

const Self = @This();

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn reset(self: *Self) void {
    self.arena.deinit();
    self.arena = std.heap.ArenaAllocator.init(self.allocator);
}

pub fn format(self: *Self, comptime fmt: []const u8, args: anytype) ![:0]const u8 {
    var textBuffer = std.ArrayList(u8).init(self.arena.allocator());
    try std.fmt.format(textBuffer.writer(), fmt, args);
    return textBuffer.toOwnedSliceSentinel(0);
}
