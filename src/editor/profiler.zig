const std = @import("std");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");

const Vec2 = imgui.Vec2;

const Self = @This();

fn Measurement(comptime T: type) type {
    return struct {
        index: usize = 0,
        samples: usize = 0,
        accumulator: T = 0,
    };
}

pub var g_profiler: ?*Self = null;

allocator: std.mem.Allocator,
timings: std.StringHashMap(std.fifo.LinearFifo(Measurement(f64), .Dynamic)),
counts: std.StringHashMap(std.fifo.LinearFifo(Measurement(u64), .Dynamic)),
maxRecordBufferCount: usize = 400,
smoothCount: usize = 25,
scale: f64 = 20,
selected: ?[]const u8 = null,
index: u64 = 0,

pub fn init(allocator: std.mem.Allocator, init_global: bool) !*Self {
    var self = try allocator.create(Self);

    self.* = Self{
        .allocator = allocator,
        .timings = std.StringHashMap(std.fifo.LinearFifo(Measurement(f64), .Dynamic)).init(allocator),
        .counts = std.StringHashMap(std.fifo.LinearFifo(Measurement(u64), .Dynamic)).init(allocator),
    };

    if (init_global) {
        g_profiler = self;
    }

    return self;
}

pub fn deinit(self: *Self) void {
    var iter = self.timings.valueIterator();
    while (iter.next()) |fifo| {
        fifo.deinit();
    }
    self.timings.deinit();

    var iter2 = self.counts.valueIterator();
    while (iter2.next()) |fifo| {
        fifo.deinit();
    }
    self.counts.deinit();

    self.allocator.destroy(self);
}

pub fn beginFrame(self: *Self) !void {
    self.index += 1;

    var iter = self.timings.valueIterator();
    while (iter.next()) |fifo| {
        if (fifo.count >= self.maxRecordBufferCount) _ = fifo.readItem();
        try fifo.writeItem(.{ .index = self.index });
    }
}

pub fn lastMeasurement(comptime T: type, fifo: *std.fifo.LinearFifo(T, .Dynamic)) *T {
    std.debug.assert(fifo.count > 0);

    var index = fifo.head + (fifo.count - 1);
    index &= fifo.buf.len - 1;
    return &fifo.buf[index];
}

fn recordIntoFifo(self: *Self, comptime T: type, measurements: *std.StringHashMap(std.fifo.LinearFifo(Measurement(T), .Dynamic)), name: []const u8, value: T, samples: u64) !void {
    if (measurements.getPtr(name)) |fifo| {
        if (fifo.count == 0) try fifo.writeItem(.{ .index = self.index });

        var last = lastMeasurement(Measurement(T), fifo);
        if (last.index != self.index) {
            if (fifo.count >= self.maxRecordBufferCount) _ = fifo.readItem();
            try fifo.writeItem(.{ .index = self.index });
            last = lastMeasurement(Measurement(T), fifo);
        }

        last.samples += samples;
        last.accumulator += value;
    } else {
        var fifo = std.fifo.LinearFifo(Measurement(T), .Dynamic).init(self.allocator);
        try fifo.writeItem(.{ .index = self.index, .samples = 1, .accumulator = value });
        try measurements.put(name, fifo);
    }
}

pub fn recordCount(self: *Self, name: []const u8, value: u64, samples: u64) !void {
    try self.recordIntoFifo(u64, &self.counts, name, value, samples);
}

pub fn recordTime(self: *Self, name: []const u8, value: f64, samples: u64) !void {
    try self.recordIntoFifo(f64, &self.timings, name, value, samples);
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
                imgui.PushIDPtr(&entry);
                defer imgui.PopID();

                imgui.TableNextRow(.{}, 0);
                _ = imgui.TableSetColumnIndex(0);
                imgui.Text("%.*s", entry.key_ptr.len, entry.key_ptr.ptr);
                if (imgui.IsItemHovered()) {
                    self.selected = entry.key_ptr.*;
                }

                if (entry.value_ptr.count > 0) {
                    var accumulator: f64 = 0;
                    var avgAccumulator: f64 = 0;
                    var samplesAccumulator: f64 = 0;
                    var i: usize = 0;
                    while (i < self.smoothCount and i < entry.value_ptr.count) : (i += 1) {
                        const measurement = entry.value_ptr.peekItem(entry.value_ptr.count - i - 1);
                        accumulator += measurement.accumulator;
                        avgAccumulator += if (measurement.samples > 0) measurement.accumulator / @intToFloat(f64, measurement.samples) else 0;
                        samplesAccumulator += @intToFloat(f64, measurement.samples);
                    }

                    _ = imgui.TableSetColumnIndex(1);
                    const avg = accumulator / @intToFloat(f64, i);
                    const avgAvg = avgAccumulator / @intToFloat(f64, i);
                    const avgSamples = samplesAccumulator / @intToFloat(f64, i);
                    imgui.Text("%.3f  %.3f (%.2f)", @floatCast(f32, avg), @floatCast(f32, avgAvg), @floatCast(f32, avgSamples));
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
                const measurement = entry.value_ptr.peekItem(i);
                const x1 = @intToFloat(f32, i) / @intToFloat(f32, self.maxRecordBufferCount) * canvas_sz.x + canvas_p0.x;
                const x2 = @intToFloat(f32, i + 1) / @intToFloat(f32, self.maxRecordBufferCount) * canvas_sz.x + canvas_p0.x;

                const y = @floatCast(f32, canvas_sz.y - measurement.accumulator * self.scale) + canvas_p0.y;

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
    name: []const u8,
    start: i128,
    samples: u64 = 1,

    pub inline fn end(self: *const ScopedProfile) void {
        if (g_profiler) |profiler| {
            const now = std.time.nanoTimestamp();
            const delta = now - self.start;
            const deltaMs = @intToFloat(f64, delta) / std.time.ns_per_ms;
            profiler.recordTime(self.name, deltaMs, self.samples) catch {};
        }
    }
};

pub inline fn beginScope(name: []const u8) ScopedProfile {
    return ScopedProfile{
        .name = name,
        .start = if (g_profiler != null) std.time.nanoTimestamp() else 0,
    };
}

pub inline fn beginScopeN(name: []const u8, samples: u64) ScopedProfile {
    return ScopedProfile{
        .name = name,
        .start = if (g_profiler != null) std.time.nanoTimestamp() else 0,
        .samples = samples,
    };
}

pub fn imguiDetails(self: *Self) void {
    _ = self;
}
