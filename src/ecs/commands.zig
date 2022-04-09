const std = @import("std");

const ArenaAllocator = @import("../util/arena_allocator.zig").ClearableArenaAllocator;

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

    pub fn removeComponentRaw(self: TempEntityId, component_type: Rtti.TypeId) TempEntityId {
        if (self.commands == null)
            return self;
        return self.commands.?.removeComponentRaw(self, component_type) catch return .{};
    }

    pub fn build(self: TempEntityId) EntityRef {
        return self.entity_ref;
    }
};

const Commands = union(enum) {
    CreateEntity: EntityRef,
    CreateEntityBundle: struct {
        entity_ref: EntityRef,
        component_types: []Rtti.TypeId,
        component_datas: []const []const u8,
    },
    DestroyEntity: EntityRef,
    AddComponent: struct {
        entity_ref: EntityRef,
        component_type: Rtti.TypeId,
        component_data: []const u8,
    },
    RemoveComponent: struct {
        entity_ref: EntityRef,
        component_type: Rtti.TypeId,
    },
};

commands: std.ArrayList(Commands),
component_data_arena: ArenaAllocator,
world: *World,

pub fn init(allocator: std.mem.Allocator, world: *World) Self {
    return Self{
        .commands = std.ArrayList(Commands).init(allocator),
        .component_data_arena = ArenaAllocator.init(allocator),
        .world = world,
    };
}

pub fn deinit(self: *const Self) void {
    self.commands.deinit();
    self.component_data_arena.deinit();
}

pub fn getEntity(self: *Self, entity_ref: EntityRef) TempEntityId {
    return TempEntityId{ .commands = self, .entity_ref = entity_ref };
}

pub fn createEntity(self: *Self) !TempEntityId {
    const entity = TempEntityId{ .commands = self, .entity_ref = try self.world.reserveEntity(self.world.reserveEntityId()) };
    try self.commands.append(.{ .CreateEntity = entity.entity_ref });
    return entity;
}

pub fn createEntityBundle(self: *Self, components: anytype) !TempEntityId {
    const ComponentsType = if (@typeInfo(@TypeOf(components)) == .Pointer) std.meta.Child(@TypeOf(components)) else @TypeOf(components);
    const components_ptr: *const ComponentsType = if (@typeInfo(@TypeOf(components)) == .Pointer) components else &components;

    const num_components = @typeInfo(ComponentsType).Struct.fields.len;

    const component_types = try self.component_data_arena.allocator().alloc(Rtti.TypeId, num_components);
    const component_datas = try self.component_data_arena.allocator().alloc([]u8, num_components);
    const component_data = try self.component_data_arena.allocator().alloc(u8, @sizeOf(ComponentsType));
    std.mem.copy(u8, component_data, std.mem.asBytes(components_ptr));

    const entity = TempEntityId{ .commands = self, .entity_ref = try self.world.reserveEntity(self.world.reserveEntityId()) };
    try self.commands.append(.{ .CreateEntityBundle = .{
        .entity_ref = entity.entity_ref,
        .component_types = component_types,
        .component_datas = component_datas,
    } });

    inline for (@typeInfo(ComponentsType).Struct.fields) |field, i| {
        component_types[i] = Rtti.typeId(field.field_type);
        if (@sizeOf(field.field_type) == 0) {
            component_datas[i] = &.{};
        } else {
            const index = @offsetOf(ComponentsType, field.name);
            component_datas[i] = component_data[index .. index + @sizeOf(field.field_type)];
        }
    }

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

pub fn addComponentRaw(self: *Self, entity: TempEntityId, component_type: Rtti.TypeId, data: []const u8) !TempEntityId {
    const component_data = try self.component_data_arena.allocator().alloc(u8, data.len);
    std.mem.copy(u8, component_data, data);
    try self.commands.append(.{ .AddComponent = .{
        .entity_ref = entity.entity_ref,
        .component_type = component_type,
        .component_data = component_data,
    } });
    return entity;
}

pub fn removeComponent(self: *Self, entity: TempEntityId, comptime component_type: type) !TempEntityId {
    return try self.removeComponentRaw(entity, Rtti.typeId(component_type));
}

pub fn removeComponentRaw(self: *Self, entity: TempEntityId, component_type: Rtti.TypeId) !TempEntityId {
    try self.commands.append(.{ .RemoveComponent = .{
        .entity_ref = entity.entity_ref,
        .component_type = component_type,
    } });
    return entity;
}

pub fn applyCommands(self: *Self) !void {
    // const scope = Profiler.beginScopeN("applyCommands", self.commands.items.len);
    // defer scope.end();

    defer {
        self.commands.clearRetainingCapacity();
        self.component_data_arena.reset();
    }

    for (self.commands.items) |command| {
        switch (command) {
            .CreateEntity => |entity_ref| {
                try self.world.createEntityFromReserved(entity_ref);
            },

            .CreateEntityBundle => |data| {
                try self.world.createEntityBundleFromReservedRaw(data.entity_ref, data.component_types, data.component_datas);
            },

            .DestroyEntity => |entity_ref| {
                try self.world.deleteEntity(entity_ref);
            },

            .AddComponent => |data| {
                try self.world.addComponentRaw(data.entity_ref, data.component_type, data.component_data);
            },

            .RemoveComponent => |data| {
                try self.world.removeComponent(data.entity_ref, data.component_type);
            },
        }
    }
}

pub fn imguiDetails(self: *Self) void {
    _ = self;
}
