const std = @import("std");

const EntityId = @import("../ecs/entity.zig").EntityId;
const ComponentId = @import("../ecs/entity.zig").ComponentId;
const World = @import("../ecs/world.zig");
const Tag = @import("../ecs/tag_component.zig").Tag;
const Commands = @import("../ecs/commands.zig");
const Rtti = @import("../util/rtti.zig");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");

const Self = @This();

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
default_component_arena: std.heap.ArenaAllocator,
default_componenets: std.AutoHashMap(Rtti.TypeId, ?[]const u8),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .default_component_arena = std.heap.ArenaAllocator.init(allocator),
        .default_componenets = std.AutoHashMap(Rtti.TypeId, ?[]const u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
    self.default_componenets.deinit();
    self.default_component_arena.deinit();
}

pub fn registerDefaultComponent(self: *Self, component: anytype) !void {
    const Type = @TypeOf(component);
    if (@sizeOf(Type) == 0) {
        try self.default_componenets.put(Rtti.typeId(Type), null);
    } else {
        const data = try self.default_component_arena.allocator().alignedAlloc(u8, @alignOf(Type), @sizeOf(Type));
        std.mem.copy(u8, data, std.mem.asBytes(&component));
        try self.default_componenets.put(Rtti.typeId(Type), data);
    }
}

pub fn draw(self: *Self, world: *World, entityId: EntityId, commands: *Commands) !void {
    self.resetTextBuffer();

    var tagBuffer = std.mem.zeroes([1024]u8);

    _ = imgui.Begin("Details");
    if (world.getEntity(entityId)) |entity| {
        imgui.PushIDInt64(entityId);
        defer imgui.PopID();

        var has_tag = false;
        if (try world.getComponent(entityId, Tag)) |tag| {
            has_tag = true;
            imgui2.property("Tag");
            if (tag.name.len < tagBuffer.len) {
                imgui.Text("%.*s", tag.name.len, tag.name.ptr);
            } else {
                imgui.Text("Too long.");
            }
        }

        // Zero sized components
        var component_id_iter = entity.entity.chunk.table.archetype.components.iterator();
        while (component_id_iter.next()) |component_id| {
            imgui.PushIDInt(@intCast(i32, component_id));
            defer imgui.PopID();

            const component_type = world.getComponentType(component_id) orelse unreachable;
            const rtti = component_type.typeInfo;
            if (rtti.size > 0)
                continue;
            const component_name = try self.format("{s}", .{rtti.name});
            imgui.TextUnformatted(component_name.ptr);

            imgui.SameLineExt(imgui.GetWindowContentRegionWidth() - imgui.CalcTextSize("X").x - 10, -1);
            if (imgui.SmallButton("X")) {
                _ = (try commands.getEntity(entityId)).removeComponentRaw(component_type);
            }
        }

        // Components with data
        // chunk.components only includes non zero sized components.
        for (entity.entity.chunk.components) |components, i| {
            imgui.PushIDInt(@intCast(i32, i));
            defer imgui.PopID();

            const rtti = components.componentType.typeInfo;
            const component_name = try self.format("{s}", .{rtti.name});

            const open = imgui.CollapsingHeaderBoolPtrExt(
                component_name.ptr,
                null,
                imgui.TreeNodeFlags.CollapsingHeader.with(.{ .DefaultOpen = true, .AllowItemOverlap = true }),
            );

            imgui.SameLineExt(imgui.GetWindowContentRegionWidth() - imgui.CalcTextSize("X").x - 10, -1);
            if (imgui.SmallButton("X")) {
                _ = (try commands.getEntity(entityId)).removeComponentRaw(components.componentType);
            }

            if (open) {
                imgui2.anyDynamic(rtti, components.getRaw(entity.entity.index));
            }
        }

        // Buttons for adding components
        if (has_tag) {
            if (imgui.SmallButton("Add Tag")) {
                const entityHandle = try commands.getEntity(entityId);
                _ = try commands.addComponent(entityHandle, Tag{ .name = "foo" });
            }
        }

        var components_iter = self.default_componenets.iterator();
        while (components_iter.next()) |entry| {
            if (try world.hasComponent(entityId, entry.key_ptr.*))
                continue;

            const name = try self.format("Add {}", .{entry.key_ptr.*});
            if (imgui.SmallButton(name.ptr)) {
                const entityHandle = try commands.getEntity(entityId);
                if (entry.value_ptr.*) |data| {
                    _ = try commands.addComponentRaw(entityHandle, entry.key_ptr.*, data);
                } else {
                    _ = try commands.addComponentRaw(entityHandle, entry.key_ptr.*, &.{});
                }
            }
        }
    }
    imgui.End();
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
