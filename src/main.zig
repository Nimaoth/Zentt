const std = @import("std");

const Rtti = @import("rtti.zig").Rtti;
const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;

const Position = struct {
    position: [3]f32,
};

const Tag = struct {
    name: []const u8,

    pub fn format(self: *const @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "Tag{{ {s} }}", .{self.name});
    }
};
const Gravity = struct {};
const A = struct { i: i64 };
const B = struct { b: bool };
const C = struct { i: i16 = 123, b: bool = true, u: u8 = 9 };
const D = struct {};

pub fn testSystem1(query: Query(.{A})) !void {
    std.log.info("A", .{});
    var iter = query.iter();
    while (iter.next()) |entity| {
        std.log.info("{}", .{entity});
    }
}

pub fn testSystem2(query: Query(.{ A, B })) !void {
    std.log.info("A, B", .{});
    var iter = query.iter();
    while (iter.next()) |entity| {
        std.log.info("{}", .{entity});
    }
}

pub fn testSystem3(query: Query(.{ A, B, C })) !void {
    std.log.info("A, B, C", .{});
    var iter = query.iter();
    while (iter.next()) |entity| {
        std.log.info("{}", .{entity});
    }
}

pub fn testSystem4(query: Query(.{ A, B, C, D })) !void {
    std.log.info("A, B, C, D", .{});
    var iter = query.iter();
    while (iter.next()) |entity| {
        std.log.info("{}", .{entity});
    }
}

pub fn testSystem5(query: Query(.{B})) !void {
    std.log.info("B", .{});
    var iter = query.iter();
    while (iter.next()) |entity| {
        std.log.info("{}", .{entity});
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator;

    std.debug.print("\n==============================================================================================================================================\n", .{});

    var world = try World.init(allocator);
    defer world.deinit();
    defer world.dumpGraph() catch {};

    _ = try EntityBuilder.init(world, "Foo")
        .addComponent(A{ .i = 1 })
        .build();

    _ = try EntityBuilder.init(world, "Foo2")
        .addComponent(A{ .i = 2 })
        .build();

    _ = try EntityBuilder.init(world, "Bar")
        .addComponent(A{ .i = 11 })
        .addComponent(B{ .b = false })
        .build();

    _ = try EntityBuilder.init(world, "Bar2")
        .addComponent(A{ .i = 12 })
        .addComponent(B{ .b = true })
        .build();

    _ = try EntityBuilder.init(world, "Bar3")
        .addComponent(B{ .b = false })
        .addComponent(A{ .i = 13 })
        .build();

    _ = try EntityBuilder.init(world, "Baz")
        .addComponent(B{ .b = true })
        .addComponent(C{})
        .addComponent(A{ .i = 21 })
        .build();

    _ = try EntityBuilder.init(world, "Baz2")
        .addComponent(A{ .i = 22 })
        .addComponent(C{ .i = 420, .u = 69 })
        .addComponent(B{ .b = false })
        .build();

    _ = try EntityBuilder.init(world, "Tog")
        .addComponent(C{ .i = 69 })
        .addComponent(B{ .b = true })
        .addComponent(A{ .i = 31 })
        .addComponent(D{})
        .build();

    world.dump();
    try world.runSystem(testSystem1);
    try world.runSystem(testSystem2);
    try world.runSystem(testSystem3);
    try world.runSystem(testSystem4);
    try world.runSystem(testSystem5);

    // if (world.getArchetypeTable(try world.createArchetypeStruct(.{ Tag, B }))) |table| {
    //     std.log.info("Found table {}", .{table});
    //     var x = table.getTyped(.{ Tag, B });
    //     std.log.info("{}", .{x});

    //     std.log.info("B", .{});
    //     for (x.B) |*a, i| {
    //         std.log.info("[{}] {}", .{ i, a.* });
    //     }
    // }
    // if (world.getArchetypeTable(try world.createArchetypeStruct(.{ Tag, A, B }))) |table| {
    //     std.log.info("Found table {}", .{table});
    //     var x = table.getTyped(.{ Tag, A, B });
    //     std.log.info("{}", .{x});

    //     std.log.info("A", .{});
    //     for (x.A) |*a, i| {
    //         std.log.info("[{}] {}", .{ i, a.* });
    //     }

    //     std.log.info("B", .{});
    //     for (x.B) |*a, i| {
    //         std.log.info("[{}] {}", .{ i, a.* });
    //     }
    // }

    // var i: u64 = 0;
    // while (i < 100) : (i += 1) {
    //     const entity = try world.createEntity();
    //     try world.addComponent(entity.id, A{});

    //     const entity2 = try world.createEntity();
    //     try world.addComponent(entity2.id, A{});
    //     try world.addComponent(entity2.id, B{});

    //     const entity3 = try world.createEntity();
    //     try world.addComponent(entity3.id, C{});
    //     try world.addComponent(entity3.id, B{});
    //     try world.addComponent(entity3.id, A{});

    //     const entity4 = try world.createEntity();
    //     try world.addComponent(entity4.id, B{});
    //     try world.addComponent(entity4.id, D{});
    //     try world.addComponent(entity4.id, A{});
    //     try world.addComponent(entity4.id, C{});
    // }
    // world.dump();

    // const entity = try world.createEntity();
    // world.dump();
    // try world.addComponent(entity.id, Position{ .position = .{ 1, 2, 3 } });
    // world.dump();
    // try world.addComponent(entity.id, Gravity{});
    // world.dump();

    // const entity2 = try world.createEntity();
    // world.dump();
    // try world.addComponent(entity2.id, Position{ .position = .{ 4, 5, 6 } });
    // world.dump();
    // try world.addComponent(entity2.id, Gravity{});
    // world.dump();
    // try world.addComponent(entity2.id, 5);
    // world.dump();
    // try world.addComponent(entity2.id, true);
    // world.dump();

    // try world.addComponent(entity.id, false);
    // world.dump();
    // try world.addComponent(entity.id, 69);
    // world.dump();

    // try world.addComponent(entity2.id, @intCast(u8, 5));
    // world.dump();

    // world.dump();
}
