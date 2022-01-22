const std = @import("std");
const Archetype = @import("archetype.zig");
const ArchetypeTable = @import("archetype_table.zig");
const World = @import("world.zig");

//digraph graphname {
//    "A" -> {B C}
//    "A" -> X
//    X -> " lol hi"
//}
const Self = @This();

pub fn init(writer: anytype) !Self {
    try writer.writeAll("digraph Archetypes {");
    return Self{};
}

pub fn deinit(self: *Self, writer: anytype) void {
    _ = self;
    writer.writeAll("\n}") catch {};
}

fn newLine(self: *Self, writer: anytype) anyerror!void {
    _ = self;
    try writer.writeAll("\n    ");
}

fn printTable(self: *Self, writer: anytype, table: *const ArchetypeTable) anyerror!void {
    _ = self;
    try std.fmt.format(writer, "\"{s}\"", .{table.archetype});
}

fn printConnection(self: *Self, writer: anytype, from: *const ArchetypeTable, to: *const ArchetypeTable, color: []const u8, diff: Archetype) anyerror!void {
    _ = self;
    try self.printTable(writer, from);
    try writer.writeAll(" -> ");
    try self.printTable(writer, to);
    try std.fmt.format(writer, " [color={s}, label=\"{}\"]", .{ color, diff });
}

pub fn printGraph(self: *Self, writer: anytype, world: *const World) anyerror!void {
    var tableIter = world.archetypeTables.valueIterator();
    while (tableIter.next()) |table| {
        try self.newLine(writer);
        try self.printTable(writer, table.*);

        var subsetIter = table.*.subsets.iterator();
        while (subsetIter.next()) |entry| {
            try self.newLine(writer);
            try self.printConnection(writer, table.*, entry.value_ptr.*, "red", Archetype.init(@intToPtr(*World, @ptrToInt(world)), 0, entry.key_ptr.*));
        }

        // var supersetIter = table.*.supersets.valueIterator();
        // while (supersetIter.next()) |superTable| {
        //     try self.newLine(writer);
        //     try self.printConnection(writer, table.*, superTable.*, "green");
        // }
    }
}
