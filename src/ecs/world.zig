const std = @import("std");

const ArchetypeTable = @import("archetype_table.zig");
const Chunk = @import("chunk.zig");
const Archetype = @import("archetype.zig");
const Entity = @import("entity.zig");
const DotPrinter = @import("dot_printer.zig");
const Query = @import("query.zig").Query;
const SystemParameterType = @import("system_parameter_type.zig").SystemParameterType;

const Rtti = @import("../util/rtti.zig");
const BitSet = @import("../util/bit_set.zig");

const imgui = @import("../editor/imgui.zig");
const imgui2 = @import("../editor/imgui2.zig");

const Profiler = @import("../editor/profiler.zig");

pub const EntityId = u64;
pub const ComponentId = u64;

pub const EntityRef = struct {
    id: EntityId,
    entity: *Entity,

    pub fn get(self: *const @This()) ?*Entity {
        if (self.isValid()) {
            return self.entity;
        } else {
            return null;
        }
    }

    pub fn isValid(self: *const @This()) bool {
        return self.id == self.entity.id and self.id != 0;
    }
};

const System = struct {
    const InvokeFunction = fn (world: *Self) anyerror!void;

    name: [*:0]const u8,
    invoke: InvokeFunction,
    enabled: bool = true,
};

const ComponentInfo = struct {
    id: u64,
};

const IntContext = struct {
    pub fn hash(ctx: @This(), key: u64) u64 {
        _ = ctx;
        var x = key;
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        x = x ^ (x >> 31);
        return x;
    }

    pub fn eql(ctx: @This(), a: u64, b: u64) bool {
        _ = ctx;
        return a == b;
    }
};

const EntityMap = std.HashMap(u64, *Entity, std.hash_map.AutoContext(u64), 10);

allocator: std.mem.Allocator,
globalPool: std.heap.ArenaAllocator,
entityArena: std.heap.ArenaAllocator,
resourceAllocator: std.heap.ArenaAllocator,

archetypeTables: std.HashMap(*ArchetypeTable, *ArchetypeTable, ArchetypeTable.HashTableContext, 80),
baseArchetypeTable: *ArchetypeTable,
entityPool: std.ArrayList(*Entity),

entityMaps: std.ArrayList(EntityMap),
nextEntityId: EntityId = 1,
components: std.AutoHashMap(Rtti.TypeId, ComponentInfo),
componentIdToComponentType: std.ArrayList(Rtti.TypeId),
frameSystems: std.ArrayList(System),
renderSystems: std.ArrayList(System),

//  We store pointers to external resources (managed outside of world)
// and internal resources (managed by this world) in here.
// Internal resources are allocated using .resourceAllocator
// and are not freed individually, so this is fine.
resources: std.AutoHashMap(Rtti.TypeId, *u8),

entity_maps_mask: u64 = 0,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !*Self {
    var world = try allocator.create(Self);

    world.* = Self{
        .allocator = allocator,
        .baseArchetypeTable = undefined,
        .globalPool = std.heap.ArenaAllocator.init(allocator),
        .entityArena = std.heap.ArenaAllocator.init(allocator),
        .resourceAllocator = std.heap.ArenaAllocator.init(allocator),
        .archetypeTables = @TypeOf(world.archetypeTables).init(allocator),
        .entityPool = @TypeOf(world.entityPool).init(allocator),
        .entityMaps = @TypeOf(world.entityMaps).init(allocator),
        .components = @TypeOf(world.components).init(allocator),
        .componentIdToComponentType = @TypeOf(world.componentIdToComponentType).init(allocator),
        .frameSystems = @TypeOf(world.frameSystems).init(allocator),
        .renderSystems = @TypeOf(world.renderSystems).init(allocator),
        .resources = @TypeOf(world.resources).init(allocator),
    };

    const entity_maps_size = 128;
    try world.entityMaps.resize(entity_maps_size);
    world.entity_maps_mask = entity_maps_size - 1;
    for (world.entityMaps.items) |*map| {
        map.* = EntityMap.init(allocator);
    }

    // Create archetype table for empty entities.
    var archetype = try world.createArchetypeStruct(.{});
    world.baseArchetypeTable = try world.getOrCreateArchetypeTable(archetype);

    return world;
}

pub fn deinit(self: *Self) void {
    var iter = self.archetypeTables.valueIterator();
    while (iter.next()) |table| {
        table.*.deinit();
    }
    self.frameSystems.deinit();
    self.renderSystems.deinit();
    self.archetypeTables.deinit();
    self.globalPool.deinit();
    self.resourceAllocator.deinit();
    for (self.entityMaps.items) |*map| {
        map.deinit();
    }
    self.entityMaps.deinit();
    self.entityPool.deinit();
    self.entityArena.deinit();
    self.components.deinit();
    self.componentIdToComponentType.deinit();
    self.resources.deinit();
    self.allocator.destroy(self);
}

pub fn dump(self: *Self) void {
    std.debug.print("------------------------- dump -------------------------------\n", .{});
    var tableIter = self.archetypeTables.iterator();
    while (tableIter.next()) |entry| {
        std.debug.print("  {}\n", .{entry.value_ptr.*});

        var chunk: ?*Chunk = entry.value_ptr.*.firstChunk;
        while (chunk) |c| {
            defer chunk = c.next;
            std.debug.print("    ", .{});
            for (c.entityIds) |entity, i| {
                if (i > 0) {
                    std.debug.print(", ", .{});
                }
                std.debug.print("{}", .{entity});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("--------------------------------------------------------------\n", .{});
}

pub fn dumpGraph(self: *Self) !void {
    var graphFile = try std.fs.cwd().createFile("graph.gv", .{});
    defer graphFile.close();
    var dotPrinter = try DotPrinter.init(graphFile.writer());
    defer dotPrinter.deinit(graphFile.writer());

    try dotPrinter.printGraph(graphFile.writer(), self);
}

pub fn addResourcePtr(self: *Self, resource: anytype) !void {
    const ResourceType = @TypeOf(resource.*);
    const rtti = Rtti.typeId(ResourceType);

    if (self.resources.contains(rtti)) {
        return error.ResourceAlreadyExists;
    }

    try self.resources.put(rtti, @ptrCast(*u8, resource));
}

pub fn addResource(self: *Self, resource: anytype) !*@TypeOf(resource) {
    const ResourceType = @TypeOf(resource);
    const rtti = Rtti.typeId(ResourceType);

    if (self.resources.contains(rtti)) {
        return error.ResourceAlreadyExists;
    }

    var newResource = try self.resourceAllocator.allocator().create(ResourceType);
    newResource.* = resource;

    try self.resources.put(rtti, @ptrCast(*u8, newResource));

    return newResource;
}

pub fn getResource(self: *Self, comptime ResourceType: type) !*ResourceType {
    const rtti = Rtti.typeId(ResourceType);
    const resourcePtr = self.resources.get(rtti) orelse return error.ResourceNotFound;
    return @ptrCast(*ResourceType, @alignCast(@alignOf(ResourceType), resourcePtr));
}

pub fn runFrameSystems(self: *Self) !void {
    for (self.frameSystems.items) |*system| {
        if (system.enabled) {
            try system.invoke(self);
        }
    }
}

pub fn runRenderSystems(self: *Self) !void {
    for (self.renderSystems.items) |*system| {
        if (system.enabled) {
            try system.invoke(self);
        }
    }
}

pub fn addSystem(self: *Self, comptime system: anytype, name: [*:0]const u8) !void {
    const wrapper = try createSystemInvokeFunction(system);
    try self.frameSystems.append(.{
        .name = name,
        .invoke = wrapper,
        .enabled = true,
    });
}

pub fn addRenderSystem(self: *Self, comptime system: anytype, name: [*:0]const u8) !void {
    const wrapper = try createSystemInvokeFunction(system);
    try self.renderSystems.append(.{
        .name = name,
        .invoke = wrapper,
        .enabled = true,
    });
}

fn createSystemInvokeFunction(comptime system: anytype) !System.InvokeFunction {
    const X = struct {
        fn invoke(world: *Self) !void {
            const ArgsType = std.meta.ArgsTuple(@TypeOf(system));
            const argsTypeInfo = @typeInfo(ArgsType).Struct;

            var args: ArgsType = undefined;

            inline for (argsTypeInfo.fields) |field| {
                const ParamType = field.field_type;
                const paramTypeInfo = @typeInfo(ParamType);

                // Pointer to the argument we want to fill out.
                var argPtr = &@field(args, field.name);

                if (paramTypeInfo == .Struct) {
                    if (@hasDecl(ParamType, "Type")) {
                        const systemParamType: SystemParameterType = ParamType.Type;
                        switch (systemParamType) {
                            .Query => try handleQuery(world, argPtr, ParamType),
                        }
                    }
                } else if (paramTypeInfo == .Pointer) {
                    // Special case: World
                    if (paramTypeInfo.Pointer.child == Self) {
                        argPtr.* = world;
                    } else {
                        // Parameter is a resource.
                        try handleResource(world, argPtr, ParamType);
                    }
                }
            }

            try @call(.{}, system, args);
        }
    };

    return X.invoke;
}

fn handleResource(world: *Self, queryArg: anytype, comptime ParamType: type) !void {
    const paramTypeInfo = @typeInfo(ParamType);
    if (paramTypeInfo != .Pointer or paramTypeInfo.Pointer.size != .One) {
        @compileError("handleResource: ParamType must be a pointer to a single item, but is " ++ @typeName(ParamType));
    }

    const ResourceType = paramTypeInfo.Pointer.child;

    const resource = try world.getResource(ResourceType);
    queryArg.* = @ptrCast(ParamType, resource);
}

fn handleQuery(world: *Self, queryArg: anytype, comptime ParamType: type) !void {
    const ComponentTypes = ParamType.ComponentTypes;

    const archetype = try world.createArchetypeStruct(ComponentTypes);

    var tables = try world.getDirectSupersetTables(archetype);
    queryArg.* = ParamType.init(tables.items, true);
}

const EntityIterator = struct {
    world: *Self,
    map_iter: EntityMap.ValueIterator,
    map_index: usize = 0,

    pub fn next(self: *@This()) ?**Entity {
        if (self.map_index >= self.world.entityMaps.items.len)
            return null;
        if (self.map_iter.next()) |e|
            return e;
        self.map_index += 1;
        if (self.map_index < self.world.entityMaps.items.len) {
            self.map_iter = self.world.entityMaps.items[self.map_index].valueIterator();
            return self.map_iter.next();
        } else {
            return null;
        }
    }

    // Returns the total number of entities
    pub fn count(self: *const @This()) usize {
        var c: usize = 0;
        for (self.world.entityMaps.items) |*map| {
            c += map.count();
        }
        return c;
    }
};

pub fn entities(self: *Self) EntityIterator {
    return .{
        .world = self,
        .map_iter = self.entityMaps.items[0].valueIterator(),
    };
}

inline fn getEntityMap(self: *Self, entity_id: EntityId) *EntityMap {
    const index = entity_id & self.entity_maps_mask;
    return &self.entityMaps.items[index];
}

pub fn reserveEntityId(self: *Self) EntityId {
    const id = self.nextEntityId;
    self.nextEntityId += 1;
    return id;
}

pub fn getEntity(self: *Self, id: EntityId) ?EntityRef {
    if (self.getEntityMap(id).get(id)) |entity| {
        return EntityRef{ .id = id, .entity = entity };
    } else {
        return null;
    }
}

pub fn createEntityWithId(self: *Self, id: EntityId) !EntityRef {
    const scope = Profiler.beginScope("createEntity");
    defer scope.end();

    var entity = if (self.entityPool.items.len > 0) self.entityPool.pop() else try self.entityArena.allocator().create(Entity);
    entity.* = try self.baseArchetypeTable.addEntity(id, .{});

    if (try self.getEntityMap(id).fetchPut(id, entity)) |old| {
        std.log.err("Failed to add entity: entity with id {} already exists", .{entity.id});

        _ = self.baseArchetypeTable.removeEntity(entity.*) orelse unreachable; // Unreachable should be ok since we remove the entity we just added.
        try self.entityPool.append(entity);
        try self.getEntityMap(old.key).put(old.key, old.value);

        return error.EntityWithIdAlreayExists;
    }

    return EntityRef{ .id = id, .entity = entity };
}

pub fn createEntity(self: *Self) !EntityRef {
    return self.createEntityWithId(self.reserveEntityId());
}

pub fn isEntityAlive(self: *Self, entityId: EntityId) bool {
    return self.getEntityMap(entityId).contains(entityId);
}

pub fn deleteEntity(self: *Self, entityId: EntityId) !void {
    const entity_map = self.getEntityMap(entityId);
    if (entity_map.get(entityId)) |entity| {
        _ = entity_map.remove(entityId);
        if (entity.chunk.removeEntity(entity.index)) |update| {
            // Another entity moved while removing entity, so update the index.
            var otherEntity = self.getEntityMap(update.entityId).getEntry(update.entityId) orelse unreachable;
            otherEntity.value_ptr.*.index = update.newIndex;
        }
        entity.* = .{};
        try self.entityPool.append(entity);
    } else {
        return error.InvalidEntityId;
    }
}

pub fn addComponent(self: *Self, entityId: EntityId, component: anytype) !EntityRef {
    if (self.getEntityMap(entityId).get(entityId)) |entity| {
        const rtti: Rtti = Rtti.typeId(@TypeOf(component));
        const componentId: u64 = try self.getComponentId(@TypeOf(component));
        var newComponents = BitSet.initEmpty();
        newComponents.set(componentId);
        var newArchetype = entity.chunk.table.archetype.addComponents(rtti.hash, newComponents);

        var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(newArchetype);

        const old_entity = entity.*;

        // copy existing entity to new table
        entity.* = try newTable.copyEntityWithComponentInto(entity, component);

        // Remove old entity
        if (old_entity.chunk.table.removeEntity(old_entity)) |update| {
            // Another entity moved while removing entity, so update the index.
            var other = self.getEntityMap(update.entityId).getEntry(update.entityId) orelse unreachable;
            other.value_ptr.index = update.newIndex;
        }

        return .{ .id = entity.id, .entity = entity };
    } else {
        return error.InvalidEntity;
    }
}

pub fn addComponentRaw(self: *Self, entityId: EntityId, componentType: Rtti.TypeId, componentData: []const u8) !EntityRef {
    if (self.getEntityMap(entityId).get(entityId)) |entity| {
        const componentId: u64 = try self.getComponentIdForRtti(componentType);
        var newComponents = BitSet.initEmpty();
        newComponents.set(componentId);
        var newArchetype = entity.chunk.table.archetype.addComponents(componentType.typeInfo.hash, newComponents);

        var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(newArchetype);

        const old_entity = entity.*;

        // copy existing entity to new table
        entity.* = try newTable.copyEntityWithComponentIntoRaw(entity.*, componentType, componentData);

        // Remove old entity
        if (old_entity.chunk.table.removeEntity(old_entity)) |update| {
            // Another entity moved while removing entity, so update the index.
            var other = self.getEntityMap(update.entityId).getEntry(update.entityId) orelse unreachable;
            other.value_ptr.*.index = update.newIndex;
        }

        return EntityRef{ .id = entity.id, .entity = entity };
    } else {
        return error.InvalidEntity;
    }
}

pub fn removeComponent(self: *Self, entityId: EntityId, componentType: Rtti.TypeId) !EntityRef {
    if (self.getEntityMap(entityId).get(entityId)) |entity| {
        const componentId: u64 = try self.getComponentIdForRtti(componentType);
        var componentIds = BitSet.initEmpty();
        componentIds.set(componentId);
        var newArchetype = entity.chunk.table.archetype.removeComponents(componentType.typeInfo.hash, componentIds);

        var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(newArchetype);

        const old_entity = entity.*;

        // copy existing entity to new table
        entity.* = try newTable.copyEntityIntoRaw(entity.*);

        // Remove old entity
        if (old_entity.chunk.table.removeEntity(old_entity)) |update| {
            // Another entity moved while removing entity, so update the index.
            var other = self.getEntityMap(update.entityId).getEntry(update.entityId) orelse unreachable;
            other.value_ptr.*.index = update.newIndex;
        }

        return EntityRef{ .id = entity.id, .entity = entity };
    } else {
        return error.InvalidEntity;
    }
}

pub fn getComponentType(self: *const Self, componentId: ComponentId) ?Rtti.TypeId {
    if (componentId >= self.componentIdToComponentType.items.len) {
        return null;
    }
    return self.componentIdToComponentType.items[componentId];
}

pub fn getComponent(self: *Self, entityId: EntityId, comptime ComponentType: type) !?*ComponentType {
    if (self.getEntityMap(entityId).get(entityId)) |entity| {
        // Check if entity has the specified component.
        const componentId = try self.getComponentId(ComponentType);
        if (!entity.chunk.table.archetype.components.isSet(componentId)) {
            return null;
        }

        // Component exists on this entity.
        const componentIndex = entity.chunk.table.getListIndexForType(Rtti.typeId(ComponentType)) orelse unreachable;
        const rawData = entity.chunk.getComponentRaw(componentIndex, entity.index);
        std.debug.assert(rawData.len == @sizeOf(ComponentType));
        return @ptrCast(*ComponentType, @alignCast(@alignOf(ComponentType), rawData.ptr));
    } else {
        return error.InvalidEntity;
    }
}

pub fn hasComponent(self: *Self, entityId: EntityId, componentType: Rtti.TypeId) !bool {
    if (self.getEntityMap(entityId).get(entityId)) |entity| {
        // Check if entity has the specified component.
        const componentId = try self.getComponentIdForRtti(componentType);
        return entity.chunk.table.archetype.components.isSet(componentId);
    } else {
        return error.InvalidEntity;
    }
}

// Utility functions

/// Returns the id of the component with the given type.
pub fn getComponentId(self: *Self, comptime ComponentType: type) !ComponentId {
    const rtti = Rtti.typeId(ComponentType);
    if (self.components.get(rtti)) |componentInfo| {
        return componentInfo.id;
    } else {
        const componentId = self.componentIdToComponentType.items.len;
        try self.components.put(rtti, .{ .id = componentId });
        try self.componentIdToComponentType.append(rtti);
        return componentId;
    }
}

/// Returns the id of the component with the given type.
pub fn getComponentIdForRtti(self: *Self, rtti: Rtti.TypeId) !ComponentId {
    if (self.components.get(rtti)) |componentInfo| {
        return componentInfo.id;
    } else {
        const componentId = self.componentIdToComponentType.items.len;
        try self.components.put(rtti, .{ .id = componentId });
        try self.componentIdToComponentType.append(rtti);
        return componentId;
    }
}

/// Creates an archetype based on the given components.
fn createArchetypeStruct(self: *Self, comptime T: anytype) !Archetype {
    var hash: u64 = 0;
    var bitSet = BitSet.initEmpty();

    const typeInfo = @typeInfo(@TypeOf(T)).Struct;
    inline for (typeInfo.fields) |field| {
        const ComponentType = field.default_value orelse unreachable;
        std.debug.assert(@TypeOf(ComponentType) == type);
        const rtti = Rtti.typeId(ComponentType);
        bitSet.set(try self.getComponentId(ComponentType));
        hash ^= rtti.typeInfo.hash;
    }
    return Archetype.init(self, hash, bitSet);
}

/// Creates an archetype table for the given archetype.
fn createArchetypeTable(self: *Self, archetype: Archetype) !*ArchetypeTable {
    var table = try self.globalPool.allocator().create(ArchetypeTable);
    try table.init(archetype, self.allocator);

    var tableIter = self.archetypeTables.valueIterator();
    while (tableIter.next()) |otherTable| {
        if (table.archetype.components.isSubSetOf(otherTable.*.archetype.components)) {
            try table.subsets.put(otherTable.*.archetype.components.without(table.archetype.components), otherTable.*);
            try otherTable.*.supersets.put(otherTable.*.archetype.components.without(table.archetype.components), table);
        }
        if (table.archetype.components.isSuperSetOf(otherTable.*.archetype.components)) {
            try table.supersets.put(table.archetype.components.without(otherTable.*.archetype.components), otherTable.*);
            try otherTable.*.subsets.put(table.archetype.components.without(otherTable.*.archetype.components), table);
        }
    }

    try self.archetypeTables.put(table, table);
    return table;
}

/// Returns the archetype table associated with the given archetype. Creates a new table if it doesn't exist yet.
fn getOrCreateArchetypeTable(self: *Self, archetype: Archetype) !*ArchetypeTable {
    if (self.archetypeTables.getKeyAdapted(&archetype, Archetype.HashTableContext{})) |table| {
        return table;
    } else {
        return try self.createArchetypeTable(try archetype.clone());
    }
}

/// Returns a list of all archetype tables which include all components of 'archetype'
fn getDirectSupersetTables(self: *Self, archetype: Archetype) !std.ArrayList(*ArchetypeTable) {
    var result = std.ArrayList(*ArchetypeTable).init(self.globalPool.allocator());

    var table = try self.getOrCreateArchetypeTable(archetype);
    try result.append(table);
    var iter = table.subsets.valueIterator();
    while (iter.next()) |super| {
        try result.append(super.*);
    }

    return result;
}
