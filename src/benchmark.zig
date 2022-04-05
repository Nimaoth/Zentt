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

pub fn main() !void {
    std.debug.print("Benchmarking zentt\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entity_count = 10_000_000;
    const iterations = 10;

    try createEntities(allocator, iterations, entity_count);
    try createEntitiesAddOneComp(allocator, iterations, entity_count);
    try iterEntitiesOneComp(allocator, iterations, entity_count);

    // var world = try World.init(allocator);
    // defer world.deinit();

    // var commands = try world.addResource(Commands.init(allocator, world));
    // defer commands.deinit();

    // var entities = std.ArrayList(EntityRef).init(allocator);
    // defer entities.deinit();

    // var k: u64 = 0;

    // std.debug.print("Create/Destroy Benchmarks\n", .{});

    // k = 0;
    // while (k < 5) : (k += 1) {
    //     {
    //         const start = std.time.nanoTimestamp();
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             _ = try world.createEntity();
    //         }

    //         const now = std.time.nanoTimestamp();
    //         const delta = now - start;
    //         const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //         std.debug.print("    Create: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });
    //     }

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         const start = std.time.nanoTimestamp();
    //         var i: usize = 0;
    //         while (i < entities.items.len) : (i += 1) {
    //             // try world.deleteEntity(entities.items[i]);
    //             try world.deleteEntity(entities.items[entities.items.len - i - 1]);
    //         }

    //         const now = std.time.nanoTimestamp();
    //         const delta = now - start;
    //         const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //         std.debug.print("    Destroy: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });
    //     }
    // }

    // std.debug.print("Iteration Benchmarks\n", .{});

    // std.debug.print("  Benchmark: Iterate {} entities with one component\n", .{entity_count});
    // k = 0;
    // while (k < 3) : (k += 1) {
    //     {
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             const entity = try world.createEntity();
    //             try world.addComponent(entity, PositionComponent{});
    //         }
    //     }

    //     const start = std.time.nanoTimestamp();
    //     {
    //         var query = try world.query(.{PositionComponent});
    //         defer query.deinit();
    //         var iter = query.iter();
    //         while (iter.next()) |entity| {
    //             g_entity = black_box(entity.ref.*);
    //             g_position = black_box(entity.position.*);
    //         }
    //     }

    //     const now = std.time.nanoTimestamp();
    //     const delta = now - start;
    //     const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //     std.debug.print("    Elapsed: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         var i: usize = entities.items.len;
    //         while (i > 0) : (i -= 1) {
    //             try world.deleteEntity(entities.items[i - 1]);
    //         }
    //     }
    // }

    // std.debug.print("  Benchmark: Iterate {} entities with one component manually\n", .{entity_count});
    // k = 0;
    // while (k < 3) : (k += 1) {
    //     {
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             const entity = try world.createEntity();
    //             try world.addComponent(entity, PositionComponent{});
    //         }
    //     }

    //     const start = std.time.nanoTimestamp();
    //     {
    //         var query = try world.query(.{PositionComponent});
    //         defer query.deinit();

    //         for (query.chunks) |chunk| {
    //             const component_index = chunk.table.getListIndexForType(Rtti.typeId(PositionComponent)) orelse unreachable;
    //             const uiae = chunk.entity_refs;
    //             const components = std.mem.bytesAsSlice(PositionComponent, chunk.getComponents(component_index).data);

    //             var i: usize = 0;
    //             while (i < chunk.count) : (i += 1) {
    //                 g_entity = black_box(uiae[i]);
    //                 g_position = black_box(components[i]);
    //             }
    //         }
    //     }

    //     const now = std.time.nanoTimestamp();
    //     const delta = now - start;
    //     const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //     std.debug.print("    Elapsed: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });
    //     // std.debug.print("    {}, {}\n", .{ g_position, sum });

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         var i: usize = entities.items.len;
    //         while (i > 0) : (i -= 1) {
    //             try world.deleteEntity(entities.items[i - 1]);
    //         }
    //     }
    // }

    // std.debug.print("  Benchmark: Iterate {} entities with two components\n", .{entity_count});
    // k = 0;
    // while (k < 3) : (k += 1) {
    //     {
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             const entity = try world.createEntity();
    //             try world.addComponent(entity, PositionComponent{});
    //             try world.addComponent(entity, DirectionComponent{});
    //         }
    //     }

    //     const start = std.time.nanoTimestamp();
    //     {
    //         var query = try world.query(.{ PositionComponent, DirectionComponent });
    //         defer query.deinit();
    //         var iter = query.iter();
    //         while (iter.next()) |entity| {
    //             g_entity = black_box(entity.ref.*);
    //             g_position = black_box(entity.position.*);
    //             g_direction = black_box(entity.direction.*);
    //         }
    //     }

    //     const now = std.time.nanoTimestamp();
    //     const delta = now - start;
    //     const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //     std.debug.print("    Elapsed: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         var i: usize = entities.items.len;
    //         while (i > 0) : (i -= 1) {
    //             try world.deleteEntity(entities.items[i - 1]);
    //         }
    //     }
    // }

    // k = 0;
    // std.debug.print("  Benchmark: Iterate {} entities with two components, but only use one\n", .{entity_count});
    // while (k < 3) : (k += 1) {
    //     {
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             const entity = try world.createEntity();
    //             try world.addComponent(entity, PositionComponent{});
    //             try world.addComponent(entity, DirectionComponent{});
    //         }
    //     }

    //     const start = std.time.nanoTimestamp();
    //     {
    //         var query = try world.query(.{ PositionComponent, DirectionComponent });
    //         defer query.deinit();
    //         var iter = query.iter();
    //         while (iter.next()) |entity| {
    //             // g_entity = black_box(entity.ref.*);
    //             g_position = black_box(entity.position.*);
    //             // g_direction = black_box(entity.direction.*);
    //         }
    //     }

    //     const now = std.time.nanoTimestamp();
    //     const delta = now - start;
    //     const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //     std.debug.print("    Elapsed: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         var i: usize = entities.items.len;
    //         while (i > 0) : (i -= 1) {
    //             try world.deleteEntity(entities.items[i - 1]);
    //         }
    //     }
    // }

    // k = 0;
    // std.debug.print("  Benchmark: Iterate {} entities with three components\n", .{entity_count});
    // while (k < 3) : (k += 1) {
    //     {
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             const entity = try world.createEntity();
    //             try world.addComponent(entity, PositionComponent{});
    //             try world.addComponent(entity, DirectionComponent{});
    //             try world.addComponent(entity, ComflabulationComponent{});
    //         }
    //     }

    //     const start = std.time.nanoTimestamp();
    //     {
    //         var query = try world.query(.{ PositionComponent, DirectionComponent, ComflabulationComponent });
    //         defer query.deinit();
    //         var iter = query.iter();
    //         while (iter.next()) |entity| {
    //             g_entity = black_box(entity.ref.*);
    //             g_position = black_box(entity.position.*);
    //             g_direction = black_box(entity.direction.*);
    //             g_comflab = black_box(entity.comflabulation.*);
    //         }
    //     }

    //     const now = std.time.nanoTimestamp();
    //     const delta = now - start;
    //     const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //     std.debug.print("    Elapsed: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         var i: usize = entities.items.len;
    //         while (i > 0) : (i -= 1) {
    //             try world.deleteEntity(entities.items[i - 1]);
    //         }
    //     }
    // }

    // k = 0;
    // std.debug.print("  Benchmark: Iterate {} entities with three components, but only use one\n", .{entity_count});
    // while (k < 3) : (k += 1) {
    //     {
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             const entity = try world.createEntity();
    //             try world.addComponent(entity, PositionComponent{});
    //             try world.addComponent(entity, DirectionComponent{});
    //             try world.addComponent(entity, ComflabulationComponent{});
    //         }
    //     }

    //     const start = std.time.nanoTimestamp();
    //     {
    //         var query = try world.query(.{ PositionComponent, DirectionComponent, ComflabulationComponent });
    //         defer query.deinit();
    //         var iter = query.iter();
    //         while (iter.next()) |entity| {
    //             // g_entity = black_box(entity.ref.*);
    //             g_position = black_box(entity.position.*);
    //             // g_direction = black_box(entity.direction.*);
    //         }
    //     }

    //     const now = std.time.nanoTimestamp();
    //     const delta = now - start;
    //     const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //     std.debug.print("    Elapsed: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         var i: usize = entities.items.len;
    //         while (i > 0) : (i -= 1) {
    //             try world.deleteEntity(entities.items[i - 1]);
    //         }
    //     }
    // }

    // k = 0;
    // std.debug.print("  Benchmark: Iterate {} entities with 1/3 components\n", .{entity_count});
    // while (k < 3) : (k += 1) {
    //     {
    //         var i: usize = 0;
    //         while (i < entity_count) : (i += 1) {
    //             const entity = try world.createEntity();
    //             try world.addComponent(entity, PositionComponent{});
    //             try world.addComponent(entity, DirectionComponent{});
    //             try world.addComponent(entity, ComflabulationComponent{});
    //         }
    //     }

    //     const start = std.time.nanoTimestamp();
    //     {
    //         var query = try world.query(.{PositionComponent});
    //         defer query.deinit();
    //         var iter = query.iter();
    //         while (iter.next()) |entity| {
    //             // g_entity = black_box(entity.ref.*);
    //             g_position = black_box(entity.position.*);
    //         }
    //     }

    //     const now = std.time.nanoTimestamp();
    //     const delta = now - start;
    //     const delta_ms = @intToFloat(f64, delta) / std.time.ns_per_ms;
    //     std.debug.print("    Elapsed: {} ms ({d:.2} ns per iteration)\n", .{ @floatToInt(i64, delta_ms), delta_ms / @intToFloat(f64, entity_count) * std.time.ns_per_ms });

    //     {
    //         entities.clearRetainingCapacity();

    //         var iter = try world.entities();
    //         defer iter.deinit();
    //         while (iter.next()) |e| {
    //             try entities.append(e.ref.*);
    //         }

    //         var i: usize = entities.items.len;
    //         while (i > 0) : (i -= 1) {
    //             try world.deleteEntity(entities.items[i - 1]);
    //         }
    //     }
    // }
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

fn moveSystem(query: Query(.{ PositionComponent, DirectionComponent })) !void {
    const dt = 0.1;
    var iter = query.iter();
    while (iter.next()) |entity| {
        entity.position.x += entity.direction.x * dt;
        entity.position.y += entity.direction.y * dt;
    }
}

fn comflabSystem(query: Query(.{ComflabulationComponent})) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        entity.comflabulation.thingy *= 1.000001;
        entity.comflabulation.mingy = !entity.comflabulation.mingy;
        entity.comflabulation.dingy += 1;
    }
}

var g_entity: EntityRef = undefined;
var g_position: PositionComponent = undefined;
var g_direction: DirectionComponent = undefined;
var g_comflab: ComflabulationComponent = undefined;

pub fn createEntities(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Create {} empty entities\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var t = Timer.init();

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

    var t = Timer.init();

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

pub fn iterEntitiesOneComp(allocator: std.mem.Allocator, iterations: u64, entity_count: u64) !void {
    std.debug.print("  Iterate {} entities with PositionComponent\n", .{entity_count});

    var world = try World.init(allocator);
    defer world.deinit();

    var i: usize = 0;
    while (i < entity_count) : (i += 1) {
        const e = try world.createEntity();
        try world.addComponent(e, PositionComponent{ .x = 1 });
    }

    var t = Timer.init();

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
    start_time: i128,
    total_sum_ms: f64 = 0,
    iter_sum_ns: f64 = 0,
    count: f64 = 0,

    total: RunningMean = .{},
    iter: RunningMean = .{},

    pub fn init() @This() {
        return .{ .start_time = std.time.nanoTimestamp() };
    }

    pub fn start(self: *@This()) void {
        self.start_time = std.time.nanoTimestamp();
    }

    pub fn end(self: *@This(), count: u64) void {
        const now = std.time.nanoTimestamp();
        const delta = now - self.start_time;
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
