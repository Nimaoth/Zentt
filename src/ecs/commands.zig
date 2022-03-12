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

    pub fn removeComponentRaw(self: TempEntityId, componentType: Rtti.TypeId) TempEntityId {
        if (self.commands == null)
            return self;
        return self.commands.?.removeComponentRaw(self, componentType) catch return .{};
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
        index: usize,
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
    return self.addComponentRaw(entity, Rtti.typeId(@TypeOf(component)), std.mem.asBytes(&component));
}

pub fn addComponentRaw(self: *Self, entity: TempEntityId, componentType: Rtti.TypeId, data: []const u8) !TempEntityId {
    const dataStartIndex = self.componentData.items.len;
    try self.componentData.appendSlice(data);
    try self.commands.append(.{ .AddComponent = .{
        .index = entity.index,
        .componentType = componentType,
        .componentDataIndex = dataStartIndex,
        .componentDataLen = data.len,
    } });
    return entity;
}

pub fn removeComponent(self: *Self, entity: TempEntityId, comptime ComponentType: type) !TempEntityId {
    return try self.removeComponentRaw(entity, Rtti.typeId(ComponentType));
}

pub fn removeComponentRaw(self: *Self, entity: TempEntityId, componentType: Rtti.TypeId) !TempEntityId {
    try self.commands.append(.{ .RemoveComponent = .{
        .index = entity.index,
        .componentType = componentType,
    } });
    return entity;
}

pub fn applyCommands(self: *Self, world: *World) !void {
    defer {
        self.commands.clearRetainingCapacity();
        self.componentData.clearRetainingCapacity();
        self.entityIdMap.clearRetainingCapacity();
    }

    for (self.commands.items) |command| {
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
                const entityId = self.entityIdMap.items[data.index];
                _ = try world.removeComponent(entityId, data.componentType);
            },
        }
    }
}

pub fn imguiDetails(self: *Self) void {
    _ = self;
}
