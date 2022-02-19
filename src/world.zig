const std = @import("std");

const ArchetypeTable = @import("archetype_table.zig");
const Chunk = @import("chunk.zig");
const Archetype = @import("archetype.zig");
const Entity = @import("entity.zig");
const Rtti = @import("rtti.zig");
const BitSet = @import("bit_set.zig");
const DotPrinter = @import("dot_printer.zig");
const Query = @import("query.zig").Query;
const SystemParameterType = @import("system_parameter_type.zig").SystemParameterType;
const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");

pub const EntityId = u64;
pub const ComponentId = u64;

const System = struct {
    const InvokeFunction = fn (world: *Self) anyerror!void;

    name: [*:0]const u8,
    invoke: InvokeFunction,
    enabled: bool = true,
};

const ComponentInfo = struct {
    id: u64,
};

allocator: std.mem.Allocator,
globalPool: std.heap.ArenaAllocator,
resourceAllocator: std.heap.ArenaAllocator,

archetypeTables: std.HashMap(*ArchetypeTable, *ArchetypeTable, ArchetypeTable.HashTableContext, 80),
baseArchetypeTable: *ArchetypeTable,
entities: std.AutoHashMap(u64, Entity),
nextEntityId: EntityId = 1,
components: std.HashMap(Rtti.TypeId, ComponentInfo, Rtti.TypeId.Context, 80),
componentIdToComponentType: std.ArrayList(Rtti.TypeId),
frameSystems: std.ArrayList(System),
resources: std.HashMap(Rtti.TypeId, *u8, Rtti.TypeId.Context, 80),

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !*Self {
    var world = try allocator.create(Self);

    world.* = Self{
        .allocator = allocator,
        .baseArchetypeTable = undefined,
        .globalPool = std.heap.ArenaAllocator.init(allocator),
        .resourceAllocator = std.heap.ArenaAllocator.init(allocator),
        .archetypeTables = @TypeOf(world.archetypeTables).init(allocator),
        .entities = @TypeOf(world.entities).init(allocator),
        .components = @TypeOf(world.components).init(allocator),
        .componentIdToComponentType = @TypeOf(world.componentIdToComponentType).init(allocator),
        .frameSystems = @TypeOf(world.frameSystems).init(allocator),
        .resources = @TypeOf(world.resources).init(allocator),
    };

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
    self.archetypeTables.deinit();
    self.globalPool.deinit();
    self.resourceAllocator.deinit();
    self.entities.deinit();
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
        _ = imgui.Begin(system.name);
        _ = imgui.Checkbox("Enabled", &system.enabled);
        if (system.enabled) {
            try system.invoke(self);
        }
        imgui.End();
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

    imgui2.any(resource, @typeName(ResourceType));
}

fn handleQuery(world: *Self, queryArg: anytype, comptime ParamType: type) !void {
    const ComponentTypes = ParamType.ComponentTypes;

    const archetype = try world.createArchetypeStruct(ComponentTypes);

    var tables = try world.getDirectSupersetTables(archetype);
    queryArg.* = ParamType.init(tables.items, true);

    {
        var iter = queryArg.iter();

        var tableFlags = imgui.TableFlags{
            .Resizable = true,
            .RowBg = true,
            .Sortable = true,
        };
        tableFlags = tableFlags.with(imgui.TableFlags.Borders);
        if (imgui.BeginTable("Entities", @intCast(i32, ParamType.ComponentCount + 1), tableFlags, .{}, 0)) {
            const componentsTypeInfo = @typeInfo(@TypeOf(ParamType.ComponentTypes)).Struct;
            imgui.TableSetupColumn("ID", .{ .WidthFixed = true }, 5, 0);
            inline for (componentsTypeInfo.fields) |componentInfo| {
                const ComponentType = componentInfo.default_value orelse unreachable;
                imgui.TableSetupColumn(@typeName(ComponentType), .{}, 0, 0);
            }
            imgui.TableHeadersRow();

            defer imgui.EndTable();
            while (iter.next()) |entity| {
                imgui.TableNextRow(.{}, 0);
                _ = imgui.TableSetColumnIndex(0);
                imgui.Text("%d", entity.id);
                inline for (componentsTypeInfo.fields) |componentInfo, i| {
                    const ComponentType = componentInfo.default_value orelse unreachable;
                    _ = ComponentType;
                    _ = imgui.TableSetColumnIndex(@intCast(i32, i + 1));

                    const field = @typeInfo(@TypeOf(entity)).Struct.fields[i + 1];
                    if (field.field_type != u8) {
                        const fieldName = field.name;
                        imgui2.any(@field(entity, fieldName), "");
                    }
                }
            }
        }
    }
}

pub fn createEntity(self: *Self) !Entity {
    const entityId = self.nextEntityId;
    self.nextEntityId += 1;
    std.log.info("createEntity {}", .{entityId});

    const entity = try self.baseArchetypeTable.addEntity(entityId, .{});
    try self.entities.put(entityId, entity);
    return entity;
}

pub fn isEntityAlive(self: *Self, entityId: EntityId) bool {
    return self.entities.contains(entityId);
}

pub fn deleteEntity(self: *Self, entityId: EntityId) !void {
    if (self.entities.get(entityId)) |entity| {
        if (entity.chunk.removeEntity(entity.index)) |update| {
            // Another entity moved while removing oldEntity, so update the index.
            var otherEntity = self.entities.getEntry(update.entityId) orelse unreachable;
            otherEntity.value_ptr.index = update.newIndex;
        }
        _ = self.entities.remove(entityId);
    } else {
        return error.InvalidEntityId;
    }
}

pub fn addComponent(self: *Self, entityId: EntityId, component: anytype) !Entity {
    if (self.entities.get(entityId)) |oldEntity| {
        const rtti: Rtti = Rtti.typeId(@TypeOf(component));
        const componentId: u64 = try self.getComponentId(@TypeOf(component));
        var newComponents = BitSet.initEmpty();
        newComponents.set(componentId);
        var newArchetype = try oldEntity.chunk.table.archetype.addComponents(rtti.hash, newComponents);

        var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(newArchetype);

        // copy existing entity to new table
        // std.log.debug("add entity {} to table {}", .{ oldEntity, newArchetype });
        var newEntity = try newTable.copyEntityInto(oldEntity, component);

        // Update entities map
        try self.entities.put(newEntity.id, newEntity);

        // Remove old entity
        // std.log.debug("remove entity {} from table {}", .{ entityId, oldEntity });
        if (oldEntity.chunk.table.removeEntity(oldEntity)) |update| {
            // Another entity moved while removing oldEntity, so update the index.
            var entity = self.entities.getEntry(update.entityId) orelse unreachable;
            // std.log.debug("update index of {} from {} to {}", .{ entity.key_ptr.*, entity.value_ptr.index, update.newIndex });
            entity.value_ptr.index = update.newIndex;
        }

        return newEntity;
    } else {
        return error.InvalidEntity;
    }
}

pub fn addComponentRaw(self: *Self, entityId: EntityId, componentType: Rtti.TypeId, componentData: []const u8) !Entity {
    std.log.err("World.addComponentRaw: {*}", .{componentData.ptr});
    if (self.entities.get(entityId)) |oldEntity| {
        const componentId: u64 = try self.getComponentIdForRtti(componentType);
        var newComponents = BitSet.initEmpty();
        newComponents.set(componentId);
        var newArchetype = try oldEntity.chunk.table.archetype.addComponents(componentType.hash, newComponents);

        var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(newArchetype);

        // copy existing entity to new table
        // std.log.debug("add entity {} to table {}", .{ oldEntity, newArchetype });
        var newEntity = try newTable.copyEntityIntoRaw(oldEntity, componentType, componentData);

        // Update entities map
        try self.entities.put(newEntity.id, newEntity);

        // Remove old entity
        // std.log.debug("remove entity {} from table {}", .{ entityId, oldEntity });
        if (oldEntity.chunk.table.removeEntity(oldEntity)) |update| {
            // Another entity moved while removing oldEntity, so update the index.
            var entity = self.entities.getEntry(update.entityId) orelse unreachable;
            // std.log.debug("update index of {} from {} to {}", .{ entity.key_ptr.*, entity.value_ptr.index, update.newIndex });
            entity.value_ptr.index = update.newIndex;
        }

        return newEntity;
    } else {
        return error.InvalidEntity;
    }
}

pub fn removeComponent(self: *const Self, entityId: EntityId, componentType: Rtti.TypeId) !void {
    _ = self;
    _ = entityId;
    _ = componentType;
    // @todo
}

pub fn getComponentType(self: *const Self, componentId: ComponentId) ?Rtti.TypeId {
    if (componentId >= self.componentIdToComponentType.items.len) {
        return null;
    }
    return self.componentIdToComponentType.items[componentId];
}

pub fn getComponent(self: *Self, entityId: EntityId, comptime ComponentType: type) !?*ComponentType {
    if (self.entities.get(entityId)) |entity| {
        // Check if entity has the specified component.
        const componentId = try self.getComponentId(ComponentType);
        if (!entity.chunk.table.archetype.components.isSet(componentId)) {
            return null;
        }

        // Component exists on this entity.
        const componentIndex = entity.chunk.table.getListIndexForType(Rtti.typeId(ComponentType));
        const rawData = entity.chunk.getComponentRaw(componentIndex, entity.index);
        std.debug.assert(rawData.len == @sizeOf(ComponentType));
        return @ptrCast(*ComponentType, @alignCast(@alignOf(ComponentType), rawData.ptr));
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
        hash ^= rtti.hash;
    }
    return Archetype.init(self, hash, bitSet);
}

/// Creates an archetype table for the given archetype.
fn createArchetypeTable(self: *Self, archetype: Archetype) !*ArchetypeTable {
    std.log.info("Creating new archetype table based on {}", .{archetype});
    var table = try self.globalPool.allocator().create(ArchetypeTable);
    try table.init(archetype, self.allocator);

    var tableIter = self.archetypeTables.valueIterator();
    while (tableIter.next()) |otherTable| {
        if (table.archetype.components.isSubSetOf(otherTable.*.archetype.components)) {
            std.log.debug("add subset {} < {}", .{ table.archetype, otherTable.*.archetype });
            try table.subsets.put(otherTable.*.archetype.components.subtract(table.archetype.components), otherTable.*);
            try otherTable.*.supersets.put(otherTable.*.archetype.components.subtract(table.archetype.components), table);
        }
        if (table.archetype.components.isSuperSetOf(otherTable.*.archetype.components)) {
            std.log.debug("add superset {} > {}", .{ table.archetype, otherTable.*.archetype });
            try table.supersets.put(table.archetype.components.subtract(otherTable.*.archetype.components), otherTable.*);
            try otherTable.*.subsets.put(table.archetype.components.subtract(otherTable.*.archetype.components), table);
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
