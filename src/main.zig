const std = @import("std");

// const TypeContext = struct {
//     pub const hash = std.getAutoHashFn(std.builtin.TypeInfo, @This());
//     pub const eql = std.getAutoEqlFn(std.builtin.TypeInfo, @This());
// };
pub const TypeId = struct {
    hash: u64,
    name: []const u8,

    const Self = @This();

    pub fn init(comptime T: type) Self {
        _ = T;
        const hash = std.hash.Wyhash.hash(69, @typeName(T));
        return Self{
            .hash = hash,
            .name = @typeName(T),
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

pub const ArchetypeTable = struct {
    entities: std.ArrayList(u64),
    components: std.ArrayList(std.ArrayList(u8)),
    archetype: Archetype,

    const Self = @This();

    pub fn init(archetype: Archetype, allocator: std.mem.Allocator) !Self {
        return Self{
            .archetype = archetype,
            .entities = std.ArrayList(u64).init(allocator),
            .components = std.ArrayList(std.ArrayList(u8)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit();

        for (self.components.items) |*componentList| {
            componentList.deinit();
        }
        self.components.deinit();
    }

    const EntityIndexUpdate = struct { entityId: u64, newIndex: u64 };

    pub fn removeEntity(self: *Self, entity: Entity) ?EntityIndexUpdate {
        std.debug.assert(entity.index < self.entities.items.len and entity.table == self);
        std.log.debug("delete {} at {}", .{ entity.id, entity.index });
        _ = self.entities.swapRemove(entity.index);

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

        return Entity{ .id = entityId, .table = self, .index = self.entities.items.len - 1 };

        // @todo: add components
        // for (components) |i, component| {
        //     try self.components.items[i].append(component);
        // }
    }

    pub fn copyEntityInto(self: *Self, entity: Entity, newComponents: anytype) !Entity {
        _ = newComponents;
        // @todo: check if the provided components match the archetype

        try self.entities.append(entity.id);

        return Entity{ .id = entity.id, .table = self, .index = self.entities.items.len - 1 };

        // @todo: add components
        // for (components) |i, component| {
        //     try self.components.items[i].append(component);
        // }
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

pub const BitSet = std.bit_set.StaticBitSet(64);

// A < B = (A u B == B)

pub const Archetype = struct {
    hash: u64,
    components: BitSet,
    world: *const World,

    const Self = @This();

    pub fn init(world: *const World, hash: u64, components: BitSet) Self {
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
        var iter = self.components.iterator(.{});
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
        var archetype = try world.createArchetype(&.{});
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
        std.debug.print("Entities:\n", .{});
        var entityIter = self.entities.iterator();
        while (entityIter.next()) |entity| {
            std.debug.print("  {} -> {}\n", .{ entity.key_ptr.*, entity.value_ptr.* });
        }

        std.debug.print("Tables:\n", .{});
        var tableIter = self.archetypeTables.iterator();
        while (tableIter.next()) |entry| {
            std.debug.print("  {}\n", .{entry.value_ptr.*});

            for (entry.value_ptr.*.entities.items) |entity| {
                std.debug.print("    {}\n", .{entity});
            }
        }
        std.debug.print("--------------------------------------------------------------\n", .{});
    }

    pub fn addSystem(self: *Self, comptime System: anytype) void {
        _ = self;
        _ = System;
    }

    pub fn createEntity(self: *Self) !Entity {
        _ = self;
        const entityId = self.nextEntityId;
        self.nextEntityId += 1;
        std.log.info("createEntity {}", .{entityId});

        const entity = try self.baseArchetypeTable.addEntity(entityId, .{});
        try self.entities.put(entityId, entity);
        return entity;
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
        _ = component;

        if (self.entities.get(entityId)) |oldEntity| {
            const typeId: TypeId = TypeId.init(@TypeOf(component));
            const componentId: u64 = try self.getComponentId(typeId);
            var newComponents = BitSet.initEmpty();
            newComponents.set(componentId);
            var newArchetype = try oldEntity.table.archetype.addComponents(typeId.hash, newComponents);

            var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(newArchetype);

            // copy existing entity to new table
            // std.log.debug("add entity {} to table {}", .{ oldEntity, newArchetype });
            var newEntity = try newTable.copyEntityInto(oldEntity, .{});

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

const Position = struct {
    position: [3]f32,
};

const Gravity = struct {};

pub fn testSystem(query: Query(.{ Position, Gravity })) void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        entity.position.position[2] += 1;
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n==============================================================================================================================================\n", .{});

    var world = try World.init(allocator);
    defer world.deinit();

    const entity = try world.createEntity();
    world.dump();
    try world.addComponent(entity.id, Position{ .position = .{ 1, 2, 3 } });
    world.dump();
    try world.addComponent(entity.id, Gravity{});
    world.dump();

    const entity2 = try world.createEntity();
    world.dump();
    try world.addComponent(entity2.id, Position{ .position = .{ 4, 5, 6 } });
    world.dump();
    try world.addComponent(entity2.id, Gravity{});
    world.dump();
    try world.addComponent(entity2.id, 5);
    world.dump();
    try world.addComponent(entity2.id, true);
    world.dump();

    try world.addComponent(entity.id, false);
    world.dump();
    try world.addComponent(entity.id, 69);
    world.dump();

    try world.addComponent(entity2.id, @intCast(u8, 5));
    world.dump();

    world.addSystem(testSystem);

    world.dump();
}
