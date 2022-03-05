const std = @import("std");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");

const Vec2 = imgui.Vec2;

const Self = @This();

allocator: std.mem.Allocator,
timings: std.StringHashMap(std.fifo.LinearFifo(f64, .Dynamic)),
maxRecordBufferCount: usize = 400,
smoothCount: usize = 25,
scale: f64 = 20,
selected: ?[]const u8 = null,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .timings = std.StringHashMap(std.fifo.LinearFifo(f64, .Dynamic)).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.timings.valueIterator();
    while (iter.next()) |fifo| {
        fifo.deinit();
    }
    self.timings.deinit();
}

pub fn record(self: *Self, name: []const u8, time: f64) !void {
    if (self.timings.getPtr(name)) |value| {
        if (value.count >= self.maxRecordBufferCount) {
            _ = value.readItem();
        }
        try value.writeItem(time);
    } else {
        var fifo = std.fifo.LinearFifo(f64, .Dynamic).init(self.allocator);
        try fifo.writeItem(time);
        try self.timings.put(name, fifo);
    }
}

pub fn draw(self: *Self) !void {
    imgui.PushStyleVarVec2(.WindowPadding, Vec2{});
    defer imgui.PopStyleVar();
    const open = imgui.Begin("Profiler");
    defer imgui.End();
    if (!open)
        return;

    var textBuffer = std.ArrayList(u8).init(self.allocator);
    defer textBuffer.deinit();

    // Table of current frames values.
    {
        var tableFlags = imgui.TableFlags{
            .Resizable = true,
            .RowBg = true,
        };
        if (imgui.BeginTable("Profiles", 2, tableFlags, .{}, 0)) {
            defer imgui.EndTable();

            { // Smooth count
                imgui.TableNextRow(.{}, 0);
                _ = imgui.TableSetColumnIndex(0);
                imgui.Text("N frames to smooth");

                _ = imgui.TableSetColumnIndex(1);
                imgui2.any(&self.smoothCount, "", .{});
                if (self.smoothCount < 1) self.smoothCount = 1;
            }

            { // History size
                imgui.TableNextRow(.{}, 0);
                _ = imgui.TableSetColumnIndex(0);
                imgui.Text("History Length");

                _ = imgui.TableSetColumnIndex(1);
                imgui2.any(&self.maxRecordBufferCount, "", .{});
                if (self.maxRecordBufferCount < 5) self.maxRecordBufferCount = 5;
                if (self.maxRecordBufferCount > 500) self.maxRecordBufferCount = 500;
            }

            { // Scale
                imgui.TableNextRow(.{}, 0);
                _ = imgui.TableSetColumnIndex(0);
                imgui.Text("Scale");

                _ = imgui.TableSetColumnIndex(1);
                imgui2.any(&self.scale, "", .{});
                if (self.scale < 0.1) self.scale = 0.1;
                if (self.scale > 1000) self.scale = 1000;
            }

            imgui.Separator();

            var iter = self.timings.iterator();
            while (iter.next()) |entry| {
                imgui.TableNextRow(.{}, 0);
                _ = imgui.TableSetColumnIndex(0);
                imgui.Text("%.*s", entry.key_ptr.len, entry.key_ptr.ptr);
                if (imgui.IsItemHovered()) {
                    self.selected = entry.key_ptr.*;
                }

                _ = imgui.TableSetColumnIndex(1);

                if (entry.value_ptr.count > 0) {
                    var sum: f64 = 0;
                    var i: usize = 0;
                    while (i < self.smoothCount and i < entry.value_ptr.count) : (i += 1) {
                        sum += entry.value_ptr.peekItem(entry.value_ptr.count - i - 1);
                    }

                    const avg = sum / @intToFloat(f64, i);
                    imgui.Text("%f", @floatCast(f32, avg));
                    if (imgui.IsItemHovered()) {
                        self.selected = entry.key_ptr.*;
                    }
                }
            }
        }

        imgui.Separator();

        // Draw graph
        const canvas_p0 = imgui.GetCursorScreenPos(); // ImDrawList API uses screen coordinates!
        var canvas_sz = imgui.GetContentRegionAvail(); // Resize canvas to what's available
        if (canvas_sz.x < 50) canvas_sz.x = 50;
        if (canvas_sz.y < 50) canvas_sz.y = 50;
        const canvas_p1 = Vec2{ .x = canvas_p0.x + canvas_sz.x, .y = canvas_p0.y + canvas_sz.y };
        _ = canvas_p1;

        var drawList = imgui.GetWindowDrawList() orelse return;
        drawList.PushClipRect(canvas_p0, canvas_p1);
        defer drawList.PopClipRect();

        var iter = self.timings.iterator();
        while (iter.next()) |entry| {
            var prevY: f32 = 0;

            const color: u32 = if (self.selected) |row| blk: {
                if (std.mem.eql(u8, row, entry.key_ptr.*)) {
                    break :blk @intCast(u32, 0xff22ff22);
                } else {
                    break :blk @intCast(u32, 0xff992222);
                }
            } else @intCast(u32, 0xff992222);

            var i: usize = 0;
            while (i < entry.value_ptr.count) : (i += 1) {
                const sample = entry.value_ptr.peekItem(i);
                const x1 = @intToFloat(f32, i) / @intToFloat(f32, self.maxRecordBufferCount) * canvas_sz.x + canvas_p0.x;
                const x2 = @intToFloat(f32, i + 1) / @intToFloat(f32, self.maxRecordBufferCount) * canvas_sz.x + canvas_p0.x;

                const y = @floatCast(f32, canvas_sz.y - sample * self.scale) + canvas_p0.y;

                if (i > 0) {
                    drawList.AddLine(.{ .x = x1, .y = prevY }, .{ .x = x2, .y = y }, color);
                }

                prevY = y;
            }
        }

        var i: f32 = 0;
        const iterations = std.math.clamp(std.math.floor(canvas_sz.y / 100), 3, 6);
        while (i < iterations) : (i += 1) {
            const y = i / iterations * canvas_sz.y;
            const ms = (canvas_sz.y - y) / self.scale;

            textBuffer.clearRetainingCapacity();
            try std.fmt.format(textBuffer.writer(), "{d:.2} ms", .{ms});
            try textBuffer.append(0);
            drawList.AddLine(.{ .x = canvas_p0.x, .y = canvas_p0.y + y }, .{ .x = canvas_p1.x, .y = canvas_p0.y + y }, 0xffaaaaaa);
            drawList.AddTextVec2(.{ .x = canvas_p0.x + 5, .y = canvas_p0.y + y + 5 }, 0xff00ffff, textBuffer.items.ptr);
        }
    }
}

pub const ScopedProfile = struct {
    profiler: *Self,
    name: []const u8,
    start: i128,

    pub fn end(self: *const ScopedProfile) void {
        const now = std.time.nanoTimestamp();
        const delta = now - self.start;
        const deltaMs = @intToFloat(f64, delta) / std.time.ns_per_ms;
        self.profiler.record(self.name, deltaMs) catch {};
    }
};

pub fn beginScope(self: *Self, name: []const u8) ScopedProfile {
    return ScopedProfile{
        .profiler = self,
        .name = name,
        .start = std.time.nanoTimestamp(),
    };
}

pub fn imguiDetails(self: *Self) void {
    _ = self;
}
