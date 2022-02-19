const std = @import("std");

const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const Tag = @import("tag_component.zig").Tag;
const Rtti = @import("rtti.zig");

const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn draw(self: *Self, world: *World, entityId: EntityId) !void {
    var scratchBuffer = std.heap.ArenaAllocator.init(self.allocator);
    defer scratchBuffer.deinit();

    var tagBuffer = std.mem.zeroes([1024]u8);

    _ = imgui.Begin("Details");
    if (world.entities.get(entityId)) |entity| {
        _ = entity;
        if (try world.getComponent(entityId, Tag)) |tag| {
            imgui2.property("Tag");
            if (tag.name.len < tagBuffer.len) {
                imgui.Text("%.*s", tag.name.len, tag.name.ptr);
                // std.mem.copy(u8, tagBuffer[0..], tag.name);
                // if (imgui.InputText(null, &tagBuffer, tagBuffer.len)) {
                //     const len = std.mem.indexOf(u8, tagBuffer[0..], &.{0}) orelse unreachable;
                //     std.mem.copy(u8, @bitCast([]u8, tag.name), tagBuffer[0..len]);
                // }
            } else {
                imgui.Text("Too long.");
            }
        }

        for (entity.chunk.components) |components| {
            const rtti = components.componentType;
            var componentName = std.ArrayList(u8).init(scratchBuffer.allocator());
            try std.fmt.format(componentName.writer(), "{s}", .{rtti.name});
            try componentName.append(0);
            if (imgui.CollapsingHeaderBoolPtrExt(
                @ptrCast([*:0]const u8, componentName.items),
                null,
                imgui.TreeNodeFlags.CollapsingHeader,
            )) {
                imgui.Text("uiae");
            }
        }

        // Check if entity has the specified component.
        // const componentId = try self.getComponentId(ComponentType);
        // if (!entity.chunk.table.archetype.components.isSet(componentId)) {
        //     return null;
        // }

        // // Component exists on this entity.
        // const componentIndex = entity.chunk.table.getListIndexForType(Rtti.init(ComponentType));
        // const rawData = entity.chunk.getComponentRaw(componentIndex, entity.index);
        // std.debug.assert(rawData.len == @sizeOf(ComponentType));
        // return @ptrCast(*ComponentType, @alignCast(@alignOf(ComponentType), rawData.ptr));
    }
    imgui.End();
}
