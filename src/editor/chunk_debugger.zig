const std = @import("std");

const imgui = @import("../imgui.zig");
const imgui2 = @import("../imgui2.zig");

const World = @import("../world.zig");
const ArchetypeTable = @import("../archetype_table.zig");
const Archetype = @import("../archetype.zig");
const Chunk = @import("../chunk.zig");
const Entity = @import("../entity.zig");
const Rtti = @import("../rtti.zig");

const Vec2 = imgui.Vec2;

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

fn resetTextBuffer(self: *Self) void {
    self.arena.deinit();
    self.arena = std.heap.ArenaAllocator.init(self.allocator);
}

fn format(self: *Self, comptime fmt: []const u8, args: anytype) ![:0]const u8 {
    var textBuffer = std.ArrayList(u8).init(self.arena.allocator());
    try std.fmt.format(textBuffer.writer(), fmt, args);
    return textBuffer.toOwnedSliceSentinel(0);
}

pub fn draw(self: *Self, world: *World) !void {
    self.resetTextBuffer();
    const open = imgui.Begin("Chunks");
    defer imgui.End();
    if (!open)
        return;

    const ArchetypeTableData = struct {
        table: *ArchetypeTable,
        entityCount: usize,

        pub fn compare(context: void, lhs: @This(), rhs: @This()) bool {
            _ = context;
            return lhs.entityCount > rhs.entityCount;
        }
    };

    var tables = try std.ArrayList(ArchetypeTableData).initCapacity(self.allocator, world.archetypeTables.count());
    defer tables.deinit();
    var iter = world.archetypeTables.valueIterator();
    while (iter.next()) |table| {
        try tables.append(.{ .table = table.*, .entityCount = table.*.getEntityCount() });
    }

    std.sort.sort(ArchetypeTableData, tables.items, {}, ArchetypeTableData.compare);

    for (tables.items) |table| {
        imgui.PushIDPtr(table.table);
        defer imgui.PopID();

        const name = try self.format("{}", .{table.table.archetype});
        const collapsingHeaderOpen = imgui.CollapsingHeaderBoolPtrExt(name.ptr, null, imgui.TreeNodeFlags.CollapsingHeader.with(.{ .DefaultOpen = true }));

        const entitiesCountStr = try self.format("{}", .{table.entityCount});
        imgui.SameLineExt(imgui.GetWindowContentRegionWidth() - imgui.CalcTextSize(entitiesCountStr.ptr).x - 10, -1);
        imgui.Text("%s", entitiesCountStr.ptr);

        if (collapsingHeaderOpen) {
            var tableFlags = imgui.TableFlags{
                .Resizable = true,
                .RowBg = true,
            };
            if (imgui.BeginTable("Info", 2, tableFlags, .{}, 0)) {
                defer imgui.EndTable();

                // Entity count
                imgui.TableNextRow(.{}, 0);
                _ = imgui.TableSetColumnIndex(0);
                imgui.Text("Entity Count");

                _ = imgui.TableSetColumnIndex(1);
                imgui.Text("%llu", table.entityCount);

                // Chunks
                var nextChunk: ?*Chunk = table.table.firstChunk;
                var i: usize = 0;
                while (nextChunk) |chunk| : (i += 1) {
                    imgui.TableNextRow(.{}, 0);
                    _ = imgui.TableSetColumnIndex(0);
                    imgui.Text("Chunk %llu", i);

                    _ = imgui.TableSetColumnIndex(1);
                    imgui.Text("%llu", chunk.count);
                    nextChunk = chunk.next;
                }
            }
        }
    }
}

pub fn imguiDetails(self: *Self) void {
    _ = self;
}
