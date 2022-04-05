const std = @import("std");

const Rtti = @import("../util/rtti.zig");
const Entity = @import("entity.zig");
const EntityRef = Entity.Ref;
const EntityId = Entity.EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;
const Tag = @import("tag_component.zig").Tag;

// const Profiler = @import("../editor/profiler.zig");

const Self = @This();

const TempEntityId = struct {
    commands: ?*Self = null,
    entity_ref: EntityRef = .{},

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

    pub fn build(self: TempEntityId) EntityRef {
        return self.entity_ref;
    }
};

const Commands = union(enum) {
    CreateEntity: EntityRef,
    DestroyEntity: EntityRef,
    AddComponent: struct {
        entity_ref: EntityRef,
        componentType: Rtti.TypeId,
        componentDataIndex: usize,
        componentDataLen: usize,
    },
    RemoveComponent: struct {
        entity_ref: EntityRef,
        componentType: Rtti.TypeId,
    },
};

commands: std.ArrayList(Commands),
componentData: std.ArrayList(u8),
world: *World,

pub fn init(allocator: std.mem.Allocator, world: *World) Self {
    return Self{
        .commands = std.ArrayList(Commands).init(allocator),
        .componentData = std.ArrayList(u8).init(allocator),
        .world = world,
    };
}

pub fn deinit(self: *const Self) void {
    self.commands.deinit();
    self.componentData.deinit();
}

pub fn getComponentData(self: *const Self, index: usize, len: usize) []const u8 {
    return self.componentData.items[index..(index + len)];
}

pub fn getEntity(self: *Self, entity_ref: EntityRef) !TempEntityId {
    return TempEntityId{ .commands = self, .entity_ref = entity_ref };
}

pub fn createEntity(self: *Self) !TempEntityId {
    const entity = TempEntityId{ .commands = self, .entity_ref = try self.world.reserveEntity(self.world.reserveEntityId()) };
    try self.commands.append(.{ .CreateEntity = entity.entity_ref });
    return entity;
}

pub fn createEntityWithId(self: *Self, entity_id: EntityId) !TempEntityId {
    const entity = TempEntityId{ .commands = self, .entity_ref = try self.world.reserveEntity(entity_id) };
    try self.commands.append(.{ .CreateEntity = entity.entity_ref });
    return entity;
}

pub fn destroyEntity(self: *Self, entity_ref: EntityRef) !void {
    try self.commands.append(.{ .DestroyEntity = entity_ref });
}

pub fn addComponent(self: *Self, entity: TempEntityId, component: anytype) !TempEntityId {
    return self.addComponentRaw(entity, Rtti.typeId(@TypeOf(component)), std.mem.asBytes(&component));
}

pub fn addComponentRaw(self: *Self, entity: TempEntityId, componentType: Rtti.TypeId, data: []const u8) !TempEntityId {
    const dataStartIndex = self.componentData.items.len;
    try self.componentData.appendSlice(data);
    try self.commands.append(.{ .AddComponent = .{
        .entity_ref = entity.entity_ref,
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
        .entity_ref = entity.entity_ref,
        .componentType = componentType,
    } });
    return entity;
}

pub fn applyCommands(self: *Self) !void {
    // const scope = Profiler.beginScopeN("applyCommands", self.commands.items.len);
    // defer scope.end();

    defer {
        self.commands.clearRetainingCapacity();
        self.componentData.clearRetainingCapacity();
    }

    for (self.commands.items) |command| {
        switch (command) {
            .CreateEntity => |entity_ref| {
                try self.world.createEntityFromReserved(entity_ref);
            },

            .DestroyEntity => |entity_ref| {
                try self.world.deleteEntity(entity_ref);
            },

            .AddComponent => |data| {
                const componentData = self.getComponentData(data.componentDataIndex, data.componentDataLen);
                try self.world.addComponentRaw(data.entity_ref, data.componentType, componentData);
            },

            .RemoveComponent => |data| {
                try self.world.removeComponent(data.entity_ref, data.componentType);
            },
        }
    }
}

pub fn imguiDetails(self: *Self) void {
    _ = self;
}
