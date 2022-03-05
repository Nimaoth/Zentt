const std = @import("std");

const Rtti = @import("../util/rtti.zig");
const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;
const Tag = @import("tag_component.zig").Tag;

const Self = @This();

const TempEntityId = struct {
    commands: ?*Self = null,
    index: usize = 0,

    pub fn addComponent(self: TempEntityId, component: anytype) TempEntityId {
        if (self.commands == null)
            return self;
        return self.commands.?.addComponent(self, component) catch return .{};
    }
};

const Commands = union(enum) {
    CreateEntity: usize,
    DestroyEntity: EntityId,
    AddComponent: struct {
        index: usize,
        componentType: Rtti.TypeId,
        componentDataIndex: usize,
        componentDataLen: usize,
    },
    RemoveComponent: struct {
        entityId: EntityId,
        componentType: Rtti.TypeId,
    },
};

commands: std.ArrayList(Commands),
componentData: std.ArrayList(u8),
entityIdMap: std.ArrayList(EntityId),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .commands = std.ArrayList(Commands).init(allocator),
        .componentData = std.ArrayList(u8).init(allocator),
        .entityIdMap = std.ArrayList(EntityId).init(allocator),
    };
}

pub fn deinit(self: *const Self) void {
    self.commands.deinit();
    self.componentData.deinit();
    self.entityIdMap.deinit();
}

pub fn getComponentData(self: *const Self, index: usize, len: usize) []const u8 {
    return self.componentData.items[index..(index + len)];
}

pub fn getEntity(self: *Self, entityId: EntityId) !TempEntityId {
    const index = self.entityIdMap.items.len;
    try self.entityIdMap.append(entityId);
    return TempEntityId{ .commands = self, .index = index };
}

pub fn createEntity(self: *Self) !TempEntityId {
    const index = self.entityIdMap.items.len;
    try self.entityIdMap.append(0);
    const entity = TempEntityId{ .commands = self, .index = index };
    try self.commands.append(.{ .CreateEntity = index });
    return entity;
}

pub fn destroyEntity(self: *Self, entityId: EntityId) !void {
    try self.commands.append(.{ .DestroyEntity = entityId });
}

pub fn addComponent(self: *Self, entity: TempEntityId, component: anytype) !TempEntityId {
    const dataStartIndex = self.componentData.items.len;
    try self.componentData.appendSlice(std.mem.asBytes(&component));
    try self.commands.append(.{ .AddComponent = .{
        .index = entity.index,
        .componentType = Rtti.typeId(@TypeOf(component)),
        .componentDataIndex = dataStartIndex,
        .componentDataLen = @sizeOf(@TypeOf(component)),
    } });
    return entity;
}

pub fn removeComponent(self: *Self, entityId: EntityId, comptime ComponentType: type) !void {
    try self.commands.append(.{ .RemoveComponent = .{
        .entityId = entityId,
        .componentType = Rtti.init(ComponentType),
    } });
}

pub fn applyCommands(self: *Self, world: *World, maxCommands: u64) !u64 {
    defer {
        self.commands.clearRetainingCapacity();
        self.componentData.clearRetainingCapacity();
        self.entityIdMap.clearRetainingCapacity();
    }

    var i: u64 = 0;
    for (self.commands.items) |command| {
        defer i += 1;
        if (i >= maxCommands)
            break;
        switch (command) {
            .CreateEntity => |index| {
                const entity = try world.createEntity();
                self.entityIdMap.items[index] = entity.id;
            },

            .DestroyEntity => |entityId| {
                try world.deleteEntity(entityId);
            },

            .AddComponent => |data| {
                const entityId = self.entityIdMap.items[data.index];
                const componentData = self.getComponentData(data.componentDataIndex, data.componentDataLen);
                _ = try world.addComponentRaw(entityId, data.componentType, componentData);
            },

            .RemoveComponent => |data| {
                try world.removeComponent(data.entityId, data.componentType);
            },
        }
    }

    return i;
}

pub fn imguiDetails(self: *Self) void {
    _ = self;
}
