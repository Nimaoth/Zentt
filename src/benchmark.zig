const std = @import("std");
const Rtti = @import("util/rtti.zig");

const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;

const Profiler = @import("editor/profiler.zig");
const Details = @import("editor/details_window.zig");
const ChunkDebugger = @import("editor/chunk_debugger.zig");
const Viewport = @import("editor/viewport.zig");

const Entity = @import("ecs/entity.zig");
const EntityId = Entity.EntityId;
const EntityRef = Entity.Ref;
const ComponentId = @import("ecs/entity.zig").ComponentId;
const World = @import("ecs/world.zig");
const EntityBuilder = @import("ecs/entity_builder.zig");
const Query = @import("ecs/query.zig").Query;
const Tag = @import("ecs/tag_component.zig").Tag;
const Chunk = @import("ecs/chunk.zig");
const Commands = @import("ecs/commands.zig");

pub const query_track_iter_invalidation = true;

pub fn main() !void {
    std.debug.print("Benchmarking zentt\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entity_count = 1_000_000;
    const iterations = 10;

    try createEmptyEntities(allocator, iterations, entity_count);
    try createEntitiesAddOneComp(allocator, iterations, entity_count);
    try createEntitiesAddFiveComps(allocator, iterations, entity_count);
    try createEntitiesAddFiveCompsBundle(allocator, iterations, entity_count);
    try createEntitiesAddEightComps(allocator, iterations, entity_count);
    try createEntitiesAddEightCompsBundle(allocator, iterations, entity_count);

    try addComponent(allocator, iterations, entity_count);

    try commandsCreateEntity(allocator, iterations, entity_count);
    try commandsCreateEntityEightComps(allocator, iterations, entity_count);
    try commandsCreateEntityEightCompsBundle(allocator, iterations, entity_count);

    try commandsAddComponent(allocator, iterations, entity_count);

    try iterEntitiesOneComp(allocator, iterations, entity_count);
}

const PositionComponent = struct {
    x: f32 = 0,
    y: f32 = 0,
};

const DirectionComponent = struct {
    x: f32 = 0,
    y: f32 = 0,
};

const ComflabulationComponent = struct {
    thingy: f32 = 0,
    dingy: i32 = 0,
    mingy: bool = false,
    stringy: []const u8 = "",
};

const TestComp1 = struct {
    a: i64 = 0,
    b: f64 = 0,
};

const TestComp2 = struct {
    a: i64 = 0,
    b: f64 = 0,
};

const TestComp3 = struct {
    a: i64 = 0,
    b: f64 = 0,
};

const TestComp4 = struct {
    a: i64 = 0,
    b: f64 = 0,
};

const TestComp5 = struct {
    a: i64 = 0,
    b: f64 = 0,
    c: bool = false,
    d: [2]u64 = .{ 0, 0 },
};

const TestComp6 = struct {
    a: i64 = 0,
    b: f64 = 0,
    c: bool = false,
    d: [2]u64 = .{ 0, 0 },
};

const TestComp7 = struct {
    a: i64 = 0,
    b: f64 = 0,
    c: bool = false,
    d: [2]u64 = .{ 0, 0 },
};

pub fn createEmptyEntities(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Create {} empty entities\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        t.start();
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            _ = try world.createEntity();
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

pub fn createEntitiesAddOneComp(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Create {} entities and add PositionComponent\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        t.start();
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            const e = try world.createEntity();
            try world.addComponent(e, PositionComponent{});
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

pub fn createEntitiesAddFiveComps(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Create {} entities and add five small components\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        t.start();
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            const e = try world.createEntity();
            try world.addComponent(e, PositionComponent{});
            try world.addComponent(e, TestComp1{});
            try world.addComponent(e, TestComp2{});
            try world.addComponent(e, TestComp3{});
            try world.addComponent(e, TestComp4{});
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

pub fn createEntitiesAddFiveCompsBundle(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Create {} entities and add five small components as bundle\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        t.start();
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            _ = try world.createEntityBundle(&.{
                PositionComponent{},
                TestComp1{},
                TestComp2{},
                TestComp3{},
                TestComp4{},
            });
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

pub fn createEntitiesAddEightComps(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Create {} entities and add eight components\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        t.start();
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            const e = try world.createEntity();
            try world.addComponent(e, PositionComponent{});
            try world.addComponent(e, TestComp1{});
            try world.addComponent(e, TestComp2{});
            try world.addComponent(e, TestComp3{});
            try world.addComponent(e, TestComp4{});
            try world.addComponent(e, TestComp5{});
            try world.addComponent(e, TestComp6{});
            try world.addComponent(e, TestComp7{});
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

pub fn createEntitiesAddEightCompsBundle(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Create {} entities and add eight components as bundle\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        t.start();
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            _ = try world.createEntityBundle(&.{
                PositionComponent{},
                TestComp1{},
                TestComp2{},
                TestComp3{},
                TestComp4{},
                TestComp5{},
                TestComp6{},
                TestComp7{},
            });
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

pub fn addComponent(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Add one component to {} entities with 5 components\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var entities = try std.ArrayList(EntityRef).initCapacity(allocator, entity_count);

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();
        entities.clearRetainingCapacity();

        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            entities.appendAssumeCapacity(try world.createEntityBundle(&.{
                PositionComponent{},
                TestComp1{},
                TestComp2{},
                TestComp3{},
                TestComp4{},
            }));
        }

        t.start();
        for (entities.items) |e| {
            try world.addComponent(e, TestComp7{});
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

pub fn commandsCreateEntity(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Run {} create entity commands. \n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var commands = Commands.init(allocator, world);
    defer commands.deinit();

    var record_timer = Timer{};
    var apply_timer = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        record_timer.start();
        var i: u64 = 0;
        while (i < entity_count) : (i += 1) {
            _ = try commands.createEntity();
        }
        record_timer.endWithoutStats();

        apply_timer.start();
        try commands.applyCommands();
        apply_timer.endWithoutStats();

        std.debug.print("    Record (per entity): ", .{});
        record_timer.printStats(entity_count);
        std.debug.print("    Apply (per entity):  ", .{});
        apply_timer.printStats(entity_count);
        std.debug.print("\n", .{});
    }

    record_timer.printAvgStats();
    apply_timer.printAvgStats();
}

pub fn commandsCreateEntityEightComps(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Run {} create entity and eight add component commands. \n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var commands = Commands.init(allocator, world);
    defer commands.deinit();

    var record_timer = Timer{};
    var apply_timer = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        record_timer.start();
        var i: u64 = 0;
        while (i < entity_count) : (i += 1) {
            const e = try commands.createEntity();
            _ = e.addComponent(PositionComponent{});
            _ = e.addComponent(TestComp1{});
            _ = e.addComponent(TestComp2{});
            _ = e.addComponent(TestComp3{});
            _ = e.addComponent(TestComp4{});
            _ = e.addComponent(TestComp5{});
            _ = e.addComponent(TestComp6{});
            _ = e.addComponent(TestComp7{});
        }
        record_timer.endWithoutStats();

        apply_timer.start();
        try commands.applyCommands();
        apply_timer.endWithoutStats();

        std.debug.print("    Record (per entity): ", .{});
        record_timer.printStats(entity_count);
        std.debug.print("    Apply (per entity):  ", .{});
        apply_timer.printStats(entity_count);
        std.debug.print("\n", .{});
    }

    record_timer.printAvgStats();
    apply_timer.printAvgStats();
}

pub fn commandsCreateEntityEightCompsBundle(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Run {} create entity bundle commands with eight components. \n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var commands = Commands.init(allocator, world);
    defer commands.deinit();

    var record_timer = Timer{};
    var apply_timer = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        record_timer.start();
        var i: u64 = 0;
        while (i < entity_count) : (i += 1) {
            _ = try commands.createEntityBundle(&.{
                PositionComponent{},
                TestComp1{},
                TestComp2{},
                TestComp3{},
                TestComp4{},
                TestComp5{},
                TestComp6{},
                TestComp7{},
            });
        }
        record_timer.endWithoutStats();

        apply_timer.start();
        try commands.applyCommands();
        apply_timer.endWithoutStats();

        std.debug.print("    Record (per entity): ", .{});
        record_timer.printStats(entity_count);
        std.debug.print("    Apply (per entity):  ", .{});
        apply_timer.printStats(entity_count);
        std.debug.print("\n", .{});
    }

    record_timer.printAvgStats();
    apply_timer.printAvgStats();
}

pub fn commandsAddComponent(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Run {} add component commands. \n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var commands = Commands.init(allocator, world);
    defer commands.deinit();

    var record_timer = Timer{};
    var apply_timer = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        try world.clear();

        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            _ = try world.createEntityBundle(&.{
                PositionComponent{},
                TestComp1{},
                TestComp2{},
                TestComp3{},
                TestComp4{},
            });
        }

        var query = try world.query(.{PositionComponent});
        defer query.deinit();
        var iter = query.iter();

        record_timer.start();
        while (iter.next()) |entity| {
            _ = commands.getEntity(entity.ref.*).addComponent(TestComp7{});
        }
        record_timer.endWithoutStats();

        apply_timer.start();
        try commands.applyCommands();
        apply_timer.endWithoutStats();

        std.debug.print("    Record (per entity): ", .{});
        record_timer.printStats(entity_count);
        std.debug.print("    Apply (per entity):  ", .{});
        apply_timer.printStats(entity_count);
        std.debug.print("\n", .{});
    }

    record_timer.printAvgStats();
    apply_timer.printAvgStats();
}

pub fn iterEntitiesOneComp(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Iterate {} entities with PositionComponent\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var i: usize = 0;
    while (i < entity_count) : (i += 1) {
        const e = try world.createEntity();
        try world.addComponent(e, PositionComponent{ .x = 1 });
    }

    var t = Timer{};

    var k: u64 = 0;
    while (k < iterations) : (k += 1) {
        var query = try world.query(.{PositionComponent});
        defer query.deinit();
        var iter = query.iter();

        t.start();
        while (iter.next()) |entity| {
            entity.position.x *= 1.000001;
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

// Utilities

inline fn black_box(value: anytype) @TypeOf(value) {
    return @ptrCast(*const volatile @TypeOf(value), &value).*;
}

const RunningMean = struct {
    count: f64 = 0,
    mean: f64 = 0,
    m2: f64 = 0,

    pub fn update(self: *@This(), value: f64) void {
        self.count += 1;

        const delta = value - self.mean;
        self.mean += delta / self.count;

        const delta2 = value - self.mean;
        self.m2 += delta * delta2;
    }

    pub fn get(self: @This()) struct { mean: f64, variance: f64, sample_variance: f64 } {
        return .{
            .mean = self.mean,
            .variance = @sqrt(self.m2 / self.count),
            .sample_variance = @sqrt(self.m2 / (self.count - 1)),
        };
    }
};

const Timer = struct {
    start_time: i128 = 0,
    end_time: i128 = std.math.maxInt(i128),
    total_sum_ms: f64 = 0,
    iter_sum_ns: f64 = 0,
    count: f64 = 0,

    total: RunningMean = .{},
    iter: RunningMean = .{},

    pub fn now() @This() {
        return .{ .start_time = std.time.nanoTimestamp() };
    }

    pub fn start(self: *@This()) void {
        self.start_time = std.time.nanoTimestamp();
    }

    pub fn end(self: *@This(), count: u64) void {
        self.end_time = std.time.nanoTimestamp();
        printStats(self, count);
    }

    pub fn endWithoutStats(self: *@This()) void {
        self.end_time = std.time.nanoTimestamp();
    }

    pub fn printStats(self: *@This(), count: u64) void {
        const delta = self.end_time - self.start_time;
        const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
        self.total_sum_ms += delta_ms;
        self.iter_sum_ns += @intToFloat(f64, delta) / @intToFloat(f64, count);

        self.total.update(delta_ms);
        self.iter.update(@intToFloat(f64, delta) / @intToFloat(f64, count));

        self.count += 1;
        std.debug.print("    {}ms ({d:.2}ns)\n", .{ @floatToInt(i64, delta_ms), @intToFloat(f64, delta) / @intToFloat(f64, count) });
    }

    pub fn printAvgStats(self: *@This()) void {
        // std.debug.print("  {d:.2}ms ({d:.2}ns)\n", .{ self.total_sum_ms / self.count, self.iter_sum_ns / self.count });

        const total_result = self.total.get();
        const iter_result = self.iter.get();
        std.debug.print("  Total: {d:.2}ms ({d:.2}, {d:.2})\n", .{ total_result.mean, total_result.variance, total_result.sample_variance });
        std.debug.print("  Iter:  {d:.2}ns ({d:.2}, {d:.2})\n\n", .{ iter_result.mean, iter_result.variance, iter_result.sample_variance });
    }
};
