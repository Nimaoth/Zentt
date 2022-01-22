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

allocator: std.mem.Allocator,
globalPool: std.heap.ArenaAllocator,

archetypeTables: std.HashMap(*ArchetypeTable, *ArchetypeTable, ArchetypeTable.HashTableContext, 80),
baseArchetypeTable: *ArchetypeTable,
entities: std.AutoHashMap(u64, Entity),
nextEntityId: u64 = 1,
components: std.HashMap(Rtti, u64, Rtti.Context, 80),
componentIdToComponentType: std.ArrayList(Rtti),

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !*Self {
    var world = try allocator.create(Self);

    world.* = Self{
        .allocator = allocator,
        .baseArchetypeTable = undefined,
        .globalPool = std.heap.ArenaAllocator.init(allocator),
        .archetypeTables = @TypeOf(world.archetypeTables).init(allocator),
        .entities = @TypeOf(world.entities).init(allocator),
        .components = @TypeOf(world.components).init(allocator),
        .componentIdToComponentType = @TypeOf(world.componentIdToComponentType).init(allocator),
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
    self.entities.deinit();
    self.components.deinit();
    self.componentIdToComponentType.deinit();
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

pub fn runSystem(self: *Self, comptime system: anytype) !void {
    _ = self;
    _ = system;

    const X = struct {
        pub fn invoke(world: *Self) !void {
            const ArgsType = std.meta.ArgsTuple(@TypeOf(system));
            const argsTypeInfo = @typeInfo(ArgsType).Struct;

            var args: ArgsType = undefined;

            inline for (argsTypeInfo.fields) |field| {
                const ParamType = field.field_type;
                if (@hasDecl(ParamType, "Type")) {
                    const systemParamType: SystemParameterType = ParamType.Type;
                    switch (systemParamType) {
                        .Query => {
                            const ComponentTypes = ParamType.ComponentTypes;

                            const archetype = try world.createArchetypeStruct(ComponentTypes);

                            var tables = try world.getDirectSupersetTables(archetype);
                            @field(args, field.name) = ParamType.init(tables.items);
                        },
                    }
                }
            }

            try @call(.{}, system, args);
        }
    };

    try X.invoke(self);
}

pub fn createEntity(self: *Self, name: []const u8) !Entity {
    _ = name;
    const entityId = self.nextEntityId;
    self.nextEntityId += 1;
    std.log.info("createEntity {} '{s}'", .{ entityId, name });

    const entity = try self.baseArchetypeTable.addEntity(entityId, .{});
    try self.entities.put(entityId, entity);
    return entity;
}

pub fn createArchetypeStruct(self: *Self, comptime T: anytype) !Archetype {
    var hash: u64 = 0;
    var bitSet = BitSet.initEmpty();

    const typeInfo = @typeInfo(@TypeOf(T)).Struct;
    inline for (typeInfo.fields) |field| {
        const ComponentType = field.default_value orelse unreachable;
        std.debug.assert(@TypeOf(ComponentType) == type);
        const rtti = Rtti.init(ComponentType);
        bitSet.set(try self.getComponentId(rtti));
        hash ^= rtti.hash;
    }
    return Archetype.init(self, hash, bitSet);
}

fn hashTypes(types: []Rtti) u64 {
    var hash: u64 = 0;
    for (types) |id| {
        hash ^= id.hash;
    }
    return hash;
}

pub fn createArchetype(self: *Self, components: []Rtti) !Archetype {
    var hash = hashTypes(components);
    var bitSet = BitSet.initEmpty();
    for (components) |rtti| {
        bitSet.set(try self.getComponentId(rtti));
    }
    return Archetype.init(self, hash, bitSet);
}

pub fn createArchetypeTable(self: *Self, archetype: Archetype) !*ArchetypeTable {
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

pub fn getOrCreateArchetypeTable(self: *Self, archetype: Archetype) !*ArchetypeTable {
    if (self.archetypeTables.getKeyAdapted(&archetype, Archetype.HashTableContext{})) |table| {
        return table;
    } else {
        return try self.createArchetypeTable(try archetype.clone());
    }
}

pub fn getArchetypeTable(self: *Self, archetype: Archetype) ?*ArchetypeTable {
    return self.archetypeTables.getKeyAdapted(&archetype, Archetype.HashTableContext{});
}

pub fn getAllSupersetTablesOf(self: *Self, table: *ArchetypeTable, result: *std.AutoHashMap(*ArchetypeTable, bool)) !void {
    var iter = table.supersets.keyIterator();
    while (iter.next()) |super| {
        try result.put(super.*, false);
        try self.getAllSupersetTablesOf(super.*);
    }
}

pub fn getAllSupersetTables(self: *Self, archetype: Archetype) !std.AutoHashMap(*ArchetypeTable, bool) {
    var result = std.AutoHashMap(*ArchetypeTable, bool).init(self.allocator);

    if (self.archetypeTables.getKeyAdapted(&archetype, Archetype.HashTableContext{})) |exactMatch| {
        result.put(exactMatch, true);
        try self.getAllSupersetTablesOf(exactMatch);
    }

    return result;
}

pub fn getDirectSupersetTables(self: *Self, archetype: Archetype) !std.ArrayList(*ArchetypeTable) {
    var result = std.ArrayList(*ArchetypeTable).init(self.globalPool.allocator());

    var table = try self.getOrCreateArchetypeTable(archetype);
    try result.append(table);
    var iter = table.subsets.valueIterator();
    while (iter.next()) |super| {
        try result.append(super.*);
    }

    return result;
}

pub fn getComponentId(self: *Self, rtti: Rtti) !u64 {
    if (self.components.get(rtti)) |componentId| {
        return componentId;
    } else {
        const componentId = self.componentIdToComponentType.items.len;
        try self.components.put(rtti, componentId);
        try self.componentIdToComponentType.append(rtti);
        return componentId;
    }
}

pub fn getComponentType(self: *const Self, componentId: u64) ?Rtti {
    if (componentId >= self.componentIdToComponentType.items.len) {
        return null;
    }
    return self.componentIdToComponentType.items[componentId];
}

pub fn addComponent(self: *Self, entityId: u64, component: anytype) !Entity {
    if (self.entities.get(entityId)) |oldEntity| {
        const rtti: Rtti = Rtti.init(@TypeOf(component));
        const componentId: u64 = try self.getComponentId(rtti);
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
