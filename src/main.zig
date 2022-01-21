const std = @import("std");

pub const TypeId = struct {
    hash: u64,
    name: []const u8,
    size: u32,
    alignment: u32,

    const Self = @This();

    pub fn init(comptime T: type) Self {
        _ = T;
        const hash = std.hash.Wyhash.hash(69, @typeName(T));
        return Self{
            .hash = hash,
            .name = @typeName(T),
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
        };
    }

    const Context = struct {
        pub fn hash(context: @This(), self: Self) u64 {
            _ = context;
            return self.hash;
        }
        pub fn eql(context: @This(), a: Self, b: Self) bool {
            _ = context;

            if (a.hash != b.hash) {
                return false;
            }

            return std.mem.eql(u8, a.name, b.name);
        }
    };

    pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "{s}", .{self.name});
    }
};

//digraph graphname {
//    "A" -> {B C}
//    "A" -> X
//    X -> " lol hi"
//}
pub const DotPrinter = struct {
    const Self = @This();

    pub fn init(writer: anytype) !Self {
        try writer.writeAll("digraph Archetypes {");
        return Self{};
    }

    pub fn deinit(self: *Self, writer: anytype) void {
        _ = self;
        writer.writeAll("\n}") catch {};
    }

    fn newLine(self: *Self, writer: anytype) anyerror!void {
        _ = self;
        try writer.writeAll("\n    ");
    }

    fn printTable(self: *Self, writer: anytype, table: *const ArchetypeTable) anyerror!void {
        _ = self;
        try std.fmt.format(writer, "\"{s}\"", .{table.archetype});
    }

    fn printConnection(self: *Self, writer: anytype, from: *const ArchetypeTable, to: *const ArchetypeTable, color: []const u8, diff: Archetype) anyerror!void {
        _ = self;
        try self.printTable(writer, from);
        try writer.writeAll(" -> ");
        try self.printTable(writer, to);
        try std.fmt.format(writer, " [color={s}, label=\"{}\"]", .{ color, diff });
    }

    pub fn printGraph(self: *Self, writer: anytype, world: *const World) anyerror!void {
        var tableIter = world.archetypeTables.valueIterator();
        while (tableIter.next()) |table| {
            try self.newLine(writer);
            try self.printTable(writer, table.*);

            var subsetIter = table.*.subsets.iterator();
            while (subsetIter.next()) |entry| {
                try self.newLine(writer);
                try self.printConnection(writer, table.*, entry.value_ptr.*, "red", Archetype.init(@intToPtr(*World, @ptrToInt(world)), 0, entry.key_ptr.*));
            }

            // var supersetIter = table.*.supersets.valueIterator();
            // while (supersetIter.next()) |superTable| {
            //     try self.newLine(writer);
            //     try self.printConnection(writer, table.*, superTable.*, "green");
            // }
        }
    }
};

pub const ArchetypeTable = struct {
    const ComponentList = struct {
        data: std.ArrayListAligned(u8, 8),
        componentId: u64,
        componentType: TypeId,
        stride: u64,

        pub fn init(componentId: u64, componentType: TypeId, allocator: std.mem.Allocator) @This() {
            return @This(){
                .data = std.ArrayListAligned(u8, 8).init(allocator),
                .componentId = componentId,
                .componentType = componentType,
                .stride = if (componentType.size == 0) 0 else std.mem.alignForward(componentType.size, componentType.alignment),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.data.deinit();
        }

        pub fn removeComponent(self: *@This(), index: u64) void {
            if (self.stride == 0)
                return;

            const byteIndex = index * self.stride;
            std.debug.assert(byteIndex + self.stride <= self.data.items.len);
            const lastItemByteIndex = self.data.items.len - self.stride;

            std.log.debug("ComponentList({}, stride = {}).removeComponent({}): move component at {} to {}", .{ self.componentId, self.stride, index, lastItemByteIndex, byteIndex });
            if (byteIndex != lastItemByteIndex) {
                std.mem.copy(u8, self.data.items[byteIndex..(byteIndex + self.stride)], self.data.items[lastItemByteIndex..(lastItemByteIndex + self.stride)]);
            }
            self.data.resize(self.data.items.len - self.stride) catch unreachable;
        }

        fn getComponentRaw(self: *@This(), index: u64) ?[]u8 {
            if ((index + 1) * self.stride <= self.data.items.len) {
                const byteIndex = index * self.stride;
                return self.data.items[byteIndex..(byteIndex + self.stride)];
            } else {
                return null;
            }
        }

        fn addComponentRaw(self: *@This(), data: []const u8) !void {
            std.debug.assert(data.len == self.stride);
            const byteIndex = self.data.items.len;
            try self.data.resize(self.data.items.len + self.stride);
            std.mem.copy(u8, self.data.items[byteIndex..(byteIndex + self.stride)], data);
        }
    };

    entities: std.ArrayList(u64),
    components: std.ArrayList(ComponentList),
    typeToList: std.HashMap(TypeId, u64, TypeId.Context, 80),
    supersets: std.AutoHashMap(BitSet, *Self),
    subsets: std.AutoHashMap(BitSet, *Self),
    archetype: Archetype,

    const Self = @This();

    pub fn init(archetype: Archetype, allocator: std.mem.Allocator) !Self {
        var components = std.ArrayList(ComponentList).init(allocator);
        var typeToList = std.HashMap(TypeId, u64, TypeId.Context, 80).init(allocator);
        var iter = archetype.components.iterator();
        while (iter.next()) |componentId| {
            const componentType = archetype.world.getComponentType(componentId) orelse unreachable;
            try typeToList.put(componentType, components.items.len);
            try components.append(ComponentList.init(componentId, componentType, allocator));
        }
        return Self{
            .archetype = archetype,
            .entities = std.ArrayList(u64).init(allocator),
            .typeToList = typeToList,
            .components = components,
            .supersets = std.AutoHashMap(BitSet, *Self).init(allocator),
            .subsets = std.AutoHashMap(BitSet, *Self).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit();
        self.typeToList.deinit();
        self.supersets.deinit();
        self.subsets.deinit();

        for (self.components.items) |*componentList| {
            componentList.deinit();
        }
        self.components.deinit();
    }

    pub fn getListIndexForType(self: *const Self, typeId: TypeId) ?u64 {
        return self.typeToList.get(typeId);
    }

    pub fn getListForType(self: *const Self, typeId: TypeId) ?*ComponentList {
        if (self.getListIndexForType(typeId)) |index| {
            return &self.components.items[index];
        } else {
            return null;
        }
    }

    fn getType(comptime Components: anytype) type {
        _ = Components;
        const typeInfo = comptime blk: {
            const T = @TypeOf(Components);
            const typeInfo = @typeInfo(T).Struct;

            // Count fields with non-zero size
            const fieldsWithSize: u64 = blk2: {
                var size: u64 = 0;
                inline for (typeInfo.fields) |field| {
                    const ComponentType = field.default_value orelse unreachable;
                    if (@sizeOf(ComponentType) > 0) {
                        size += 1;
                    }
                }
                break :blk2 size;
            };

            var fields: [fieldsWithSize + 1]std.builtin.TypeInfo.StructField = undefined;

            fields[0] = .{
                .name = "entities",
                .field_type = []u64,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf([]u64),
            };

            // Fill field type info for all components with non-zero size
            var index: u64 = 1;
            inline for (typeInfo.fields) |field| {
                const ComponentType = field.default_value orelse unreachable;
                std.debug.assert(@TypeOf(ComponentType) == type);
                if (@sizeOf(ComponentType) > 0) {
                    fields[index] = .{
                        .name = @typeName(ComponentType),
                        .field_type = []ComponentType,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = @alignOf([]ComponentType),
                    };
                    index += 1;
                }
            }

            break :blk std.builtin.TypeInfo{
                .Struct = .{
                    .layout = .Auto,
                    .fields = fields[0..],
                    .decls = &.{},
                    .is_tuple = false,
                },
            };
        };
        return @Type(typeInfo);
    }

    pub fn getTyped(self: *Self, comptime Components: anytype) getType(Components) {
        _ = self;
        const T = @TypeOf(Components);
        const typeInfo = @typeInfo(T).Struct;

        var result: getType(Components) = undefined;

        result.entities = self.entities.items;
        inline for (typeInfo.fields) |field| {
            const ComponentType = field.default_value orelse unreachable;
            std.debug.assert(@TypeOf(ComponentType) == type);

            const componentType = TypeId.init(ComponentType);
            const componentId = self.archetype.world.getComponentId(componentType) catch unreachable;

            if (self.getListForType(componentType)) |componentList| {
                std.debug.assert(componentList.componentId == componentId);
                @field(result, @typeName(ComponentType)) = std.mem.bytesAsSlice(ComponentType, componentList.data.items);
            }
        }

        return result;
        // return Archetype.init(self, hash, bitSet);
    }

    const EntityIndexUpdate = struct { entityId: u64, newIndex: u64 };

    pub fn removeEntity(self: *Self, entity: Entity) ?EntityIndexUpdate {
        std.debug.assert(entity.index < self.entities.items.len and entity.table == self);
        _ = self.entities.swapRemove(entity.index);

        // Remove all components
        for (self.components.items) |*componentList| {
            componentList.removeComponent(entity.index);
        }

        if (entity.index < self.entities.items.len) {
            // The index of the last entity changed because it was moved to the current index i.
            // Update the index stored in the entities map in the world.
            return EntityIndexUpdate{ .entityId = self.entities.items[entity.index], .newIndex = entity.index };
        }

        return null;
    }

    pub fn addEntity(self: *Self, entityId: u64, components: anytype) !Entity {
        _ = components;
        // @todo: check if the provided components match the archetype

        try self.entities.append(entityId);
        std.log.info("addEntity({}): {}", .{ entityId, components });

        const typeInfo = @typeInfo(@TypeOf(components)).Struct;
        inline for (typeInfo.fields) |field| {
            const componentType = TypeId.init(field.field_type);
            if (self.getListForType(componentType)) |list| {
                try list.addComponentRaw(std.mem.asBytes(&@field(components, field.name)));
            }
        }

        return Entity{ .id = entityId, .table = self, .index = self.entities.items.len - 1 };
    }

    /// Adds a new component to the given component list and returns a pointer to the component
    fn insertComponent(self: *Self, componentTypeIndex: u64, comptime T: type, data: *const T) !*T {
        var componentList = &self.components.items[componentTypeIndex];
        const index = componentList.data.items.len;
        try componentList.data.resize(componentList.data.items.len + componentList.stride);
        var newComponent = @ptrCast(*T, @alignCast(@alignOf(T), &componentList.data.items[index]));
        newComponent.* = data.*;
        return newComponent;
    }

    pub fn copyEntityInto(self: *Self, entity: Entity, newComponent: anytype) !Entity {
        // @todo: check if the provided components match the archetype

        const ComponentType = @TypeOf(newComponent);

        std.log.info("copyEntityInto({}): {}", .{ entity, newComponent });
        // Add entity
        // const index = self.entities.count();
        try self.entities.append(entity.id);

        // Add new component
        const componentType = TypeId.init(ComponentType);
        const componentId = try self.archetype.world.getComponentId(componentType);
        if (self.getListForType(componentType)) |componentList| {
            std.debug.assert(componentList.componentId == componentId);
            try componentList.addComponentRaw(std.mem.asBytes(&newComponent));
        }

        // Copy existing components
        for (self.components.items) |*componentList| {
            if (entity.table.getListForType(componentList.componentType)) |otherList| {
                if (otherList.getComponentRaw(entity.index)) |oldComponent| {
                    try componentList.addComponentRaw(oldComponent);
                }
            }
        }

        return Entity{ .id = entity.id, .table = self, .index = self.entities.items.len - 1 };
    }

    pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "ArchetypeTable {}", .{self.archetype});
    }

    pub const HashTableContext = struct {
        pub fn hash(context: @This(), self: *Self) u64 {
            _ = context;
            return self.archetype.hash;
        }
        pub fn eql(context: @This(), a: *Self, b: *Self) bool {
            _ = context;
            var ctx = Archetype.Context{};
            return ctx.eql(&a.archetype, &b.archetype);
        }
    };
};

pub const BitSet = struct {
    const Impl = std.bit_set.StaticBitSet(64);

    bitSet: Impl,

    const Self = @This();

    pub fn initEmpty() @This() {
        return @This(){ .bitSet = Impl.initEmpty() };
    }

    pub fn set(self: *Self, index: usize) void {
        self.bitSet.set(index);
    }

    pub fn unset(self: *Self, index: usize) void {
        self.bitSet.unset(index);
    }

    pub fn setUnion(self: *Self, other: BitSet) void {
        self.bitSet.setUnion(other.bitSet);
    }

    pub fn setIntersection(self: *Self, other: BitSet) void {
        self.bitSet.setIntersection(other.bitSet);
    }

    pub fn isSubSetOf(self: *const Self, other: Self) bool {
        var sum = self.*;
        sum.setUnion(other);
        return std.meta.eql(sum, other);
    }

    pub fn isSuperSetOf(self: *const Self, other: Self) bool {
        var sum = self.*;
        sum.setUnion(other);
        return std.meta.eql(sum, self.*);
    }

    pub fn subtract(self: *const Self, other: Self) Self {
        var diff = self.*;
        var otherInverse = other;
        otherInverse.bitSet.toggleAll();
        diff.setIntersection(otherInverse);
        return diff;
    }

    pub fn iterator(self: *const Self) @TypeOf(Impl.initEmpty().iterator(.{})) {
        return self.bitSet.iterator(.{});
    }
};

// A < B = (A u B == B)

pub const Archetype = struct {
    hash: u64,
    components: BitSet,
    world: *World,

    const Self = @This();

    pub fn init(world: *World, hash: u64, components: BitSet) Self {
        return Self{
            .hash = hash,
            .components = components,
            .world = world,
        };
    }

    pub fn clone(self: *const Self) !Self {
        return Self.init(self.world, self.hash, self.components);
    }

    pub fn addComponents(self: *const Self, newHash: u64, components: BitSet) !Self {
        var newComponents = self.components;
        newComponents.setUnion(components);
        return Self.init(self.world, self.hash ^ newHash, newComponents);
    }

    const Context = struct {
        pub fn hash(context: @This(), self: *const Self) u64 {
            _ = context;
            return self.hash;
        }
        pub fn eql(context: @This(), a: *const Self, b: *Self) bool {
            _ = context;
            if (a.hash != b.hash) {
                return false;
            }

            const result = std.meta.eql(a.components, b.components);
            return result;
        }
    };

    const HashTableContext = struct {
        pub fn hash(context: @This(), self: *const Self) u64 {
            _ = context;
            return self.hash;
        }
        pub fn eql(context: @This(), a: *const Self, b: *ArchetypeTable) bool {
            _ = context;
            if (a.hash != b.archetype.hash) {
                return false;
            }

            const result = std.meta.eql(a.components, b.archetype.components);
            return result;
        }
    };

    pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "{{", .{});
        var iter = self.components.iterator();
        var i: u64 = 0;
        while (iter.next()) |componentId| {
            defer i += 1;
            if (i > 0) {
                try std.fmt.format(writer, ", ", .{});
            }
            const typeId = self.world.getComponentType(componentId) orelse unreachable;
            try std.fmt.format(writer, "{}", .{typeId});
        }
        try std.fmt.format(writer, "}}", .{});
    }
};

pub fn hashTypes(types: []TypeId) u64 {
    var hash: u64 = 0;
    for (types) |id| {
        hash ^= id.hash;
    }
    return hash;
}

pub const Entity = struct {
    id: u64,
    table: *ArchetypeTable,
    index: u64,

    const Self = @This();
};

pub const World = struct {
    allocator: std.mem.Allocator,
    globalPool: std.heap.ArenaAllocator,

    archetypeTables: std.HashMap(*ArchetypeTable, *ArchetypeTable, ArchetypeTable.HashTableContext, 80),
    baseArchetypeTable: *ArchetypeTable,
    entities: std.AutoHashMap(u64, Entity),
    nextEntityId: u64 = 1,
    components: std.HashMap(TypeId, u64, TypeId.Context, 80),
    componentIdToComponentType: std.ArrayList(TypeId),

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
        var archetype = try world.createArchetypeStruct(.{Tag});
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

            std.debug.print("    ", .{});
            for (entry.value_ptr.*.entities.items) |entity, i| {
                if (i > 0) {
                    std.debug.print(", ", .{});
                }
                std.debug.print("{}", .{entity});
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

    pub fn addSystem(self: *Self, comptime System: anytype) void {
        _ = self;
        _ = System;
    }

    pub fn createEntity(self: *Self, name: []const u8) !Entity {
        _ = name;
        const entityId = self.nextEntityId;
        self.nextEntityId += 1;
        std.log.info("createEntity {} '{s}'", .{ entityId, name });

        const tag = Tag{ .name = name };
        const entity = try self.baseArchetypeTable.addEntity(entityId, .{tag});
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
            const typeId = TypeId.init(ComponentType);
            bitSet.set(try self.getComponentId(typeId));
            hash ^= typeId.hash;
        }
        return Archetype.init(self, hash, bitSet);
    }

    pub fn createArchetype(self: *Self, components: []TypeId) !Archetype {
        var hash = hashTypes(components);
        var bitSet = BitSet.initEmpty();
        for (components) |typeId| {
            bitSet.set(try self.getComponentId(typeId));
        }
        return Archetype.init(self, hash, bitSet);
    }

    pub fn createArchetypeTable(self: *Self, archetype: Archetype) !*ArchetypeTable {
        std.log.info("Creating new archetype table based on {}", .{archetype});
        var table = try self.globalPool.allocator().create(ArchetypeTable);
        table.* = try ArchetypeTable.init(archetype, self.allocator);

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

    pub fn getComponentId(self: *Self, typeId: TypeId) !u64 {
        if (self.components.get(typeId)) |componentId| {
            return componentId;
        } else {
            const componentId = self.componentIdToComponentType.items.len;
            try self.components.put(typeId, componentId);
            try self.componentIdToComponentType.append(typeId);
            return componentId;
        }
    }

    pub fn getComponentType(self: *const Self, componentId: u64) ?TypeId {
        if (componentId >= self.componentIdToComponentType.items.len) {
            return null;
        }
        return self.componentIdToComponentType.items[componentId];
    }

    pub fn addComponent(self: *Self, entityId: u64, component: anytype) !void {
        if (self.entities.get(entityId)) |oldEntity| {
            const typeId: TypeId = TypeId.init(@TypeOf(component));
            const componentId: u64 = try self.getComponentId(typeId);
            var newComponents = BitSet.initEmpty();
            newComponents.set(componentId);
            var newArchetype = try oldEntity.table.archetype.addComponents(typeId.hash, newComponents);

            var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(newArchetype);

            // copy existing entity to new table
            // std.log.debug("add entity {} to table {}", .{ oldEntity, newArchetype });
            var newEntity = try newTable.copyEntityInto(oldEntity, component);

            // Update entities map
            try self.entities.put(newEntity.id, newEntity);

            // Remove old entity
            // std.log.debug("remove entity {} from table {}", .{ entityId, oldEntity });
            if (oldEntity.table.removeEntity(oldEntity)) |update| {
                // Another entity moved while removing oldEntity, so update the index.
                var entity = self.entities.getEntry(update.entityId) orelse unreachable;
                // std.log.debug("update index of {} from {} to {}", .{ entity.key_ptr.*, entity.value_ptr.index, update.newIndex });
                entity.value_ptr.index = update.newIndex;
            }
        } else {
            return error.InvalidEntity;
        }
    }
};

pub fn Query(comptime Q: anytype) type {
    _ = Q;
    const EntityHandle = struct {
        id: u64,
        position: *Position,
        gravity: *Gravity,
    };

    const Iterator = struct {
        const Self = @This();

        pub fn next(self: *Self) ?EntityHandle {
            _ = self;
            return null;
        }
    };

    const QueryTemplate = struct {
        const Self = @This();

        pub fn iter(self: *const Self) Iterator {
            _ = self;
            return Iterator{};
        }
    };

    return QueryTemplate;
}

pub fn testSystem(query: Query(.{ Position, Gravity })) void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        entity.position.position[2] += 1;
    }
}

const Position = struct {
    position: [3]f32,
};

const Tag = struct {
    name: []const u8,

    pub fn format(self: *const @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "Tag{{ {s} }}", .{self.name});
    }
};
const Gravity = struct {};
const A = struct { i: i64 };
const B = struct { b: bool };
const C = struct {};
const D = struct {};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator;

    std.debug.print("\n==============================================================================================================================================\n", .{});

    var world = try World.init(allocator);
    defer world.deinit();
    defer world.dumpGraph() catch {};
    var entity = try world.createEntity("Foo");
    var entity2 = try world.createEntity("Bar");

    try world.addComponent(entity.id, A{ .i = 123 });
    try world.addComponent(entity2.id, A{ .i = 456 });

    try world.addComponent(entity.id, B{ .b = true });
    try world.addComponent(entity2.id, B{ .b = false });

    entity = try world.createEntity("Hans");
    try world.addComponent(entity.id, A{ .i = 789 });

    entity = try world.createEntity("im");
    try world.addComponent(entity.id, A{ .i = 69 });
    try world.addComponent(entity.id, D{});

    entity = try world.createEntity("Glück");
    try world.addComponent(entity.id, A{ .i = 420 });
    try world.addComponent(entity.id, C{});

    world.dump();
    if (world.getArchetypeTable(try world.createArchetypeStruct(.{ Tag, A }))) |table| {
        std.log.info("Found table {}", .{table});
        var x = table.getTyped(.{ Tag, A });
        std.log.info("{}", .{x});

        std.log.info("A", .{});
        for (x.A) |*a, i| {
            std.log.info("[{}] {}", .{ i, a.* });
        }
    }
    if (world.getArchetypeTable(try world.createArchetypeStruct(.{ Tag, B }))) |table| {
        std.log.info("Found table {}", .{table});
        var x = table.getTyped(.{ Tag, B });
        std.log.info("{}", .{x});

        std.log.info("B", .{});
        for (x.B) |*a, i| {
            std.log.info("[{}] {}", .{ i, a.* });
        }
    }
    if (world.getArchetypeTable(try world.createArchetypeStruct(.{ Tag, A, B }))) |table| {
        std.log.info("Found table {}", .{table});
        var x = table.getTyped(.{ Tag, A, B });
        std.log.info("{}", .{x});

        std.log.info("A", .{});
        for (x.A) |*a, i| {
            std.log.info("[{}] {}", .{ i, a.* });
        }

        std.log.info("B", .{});
        for (x.B) |*a, i| {
            std.log.info("[{}] {}", .{ i, a.* });
        }
    }

    // var i: u64 = 0;
    // while (i < 100) : (i += 1) {
    //     const entity = try world.createEntity();
    //     try world.addComponent(entity.id, A{});

    //     const entity2 = try world.createEntity();
    //     try world.addComponent(entity2.id, A{});
    //     try world.addComponent(entity2.id, B{});

    //     const entity3 = try world.createEntity();
    //     try world.addComponent(entity3.id, C{});
    //     try world.addComponent(entity3.id, B{});
    //     try world.addComponent(entity3.id, A{});

    //     const entity4 = try world.createEntity();
    //     try world.addComponent(entity4.id, B{});
    //     try world.addComponent(entity4.id, D{});
    //     try world.addComponent(entity4.id, A{});
    //     try world.addComponent(entity4.id, C{});
    // }
    // world.dump();

    // const entity = try world.createEntity();
    // world.dump();
    // try world.addComponent(entity.id, Position{ .position = .{ 1, 2, 3 } });
    // world.dump();
    // try world.addComponent(entity.id, Gravity{});
    // world.dump();

    // const entity2 = try world.createEntity();
    // world.dump();
    // try world.addComponent(entity2.id, Position{ .position = .{ 4, 5, 6 } });
    // world.dump();
    // try world.addComponent(entity2.id, Gravity{});
    // world.dump();
    // try world.addComponent(entity2.id, 5);
    // world.dump();
    // try world.addComponent(entity2.id, true);
    // world.dump();

    // try world.addComponent(entity.id, false);
    // world.dump();
    // try world.addComponent(entity.id, 69);
    // world.dump();

    // try world.addComponent(entity2.id, @intCast(u8, 5));
    // world.dump();

    // world.addSystem(testSystem);

    // world.dump();
}
