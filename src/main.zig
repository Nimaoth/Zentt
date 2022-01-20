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
        self.archetype.deinit();
        self.entities.deinit();

        for (self.components.items) |*componentList| {
            componentList.deinit();
        }
        self.components.deinit();
    }

    pub fn removeEntity(self: *Self, entity: u64) void {
        for (self.entities.items) |entity2, i| {
            std.log.info("delete {} {}", .{ i, entity2 });
            if (entity2 == entity) {
                std.log.info("deleted", .{});
                _ = self.entities.swapRemove(i);
                break;
            }
        }
    }

    pub fn addEntity(self: *Self, entity: u64, components: anytype) !void {
        _ = components;
        // @todo: check if the provided components match the archetype

        try self.entities.append(entity);

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

    const Self = @This();

    pub fn init(hash: u64, components: BitSet) Self {
        return Self{
            .hash = hash,
            .components = components,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // self.components.deinit();
    }

    pub fn clone(self: *const Self) !Self {
        return Self.init(self.hash, self.components);
    }

    pub fn addComponents(self: *const Self, newHash: u64, components: BitSet) !Self {
        // var newComponents = try std.ArrayList(TypeId).initCapacity(self.components.allocator, self.components.items.len + components.len);
        // newComponents.appendSliceAssumeCapacity(self.components.items);
        // newComponents.appendSliceAssumeCapacity(components);
        // return Self.init(newComponents);
        var newComponents = self.components;
        newComponents.setUnion(components);
        return Self.init(self.hash ^ newHash, newComponents);
    }

    const Context = struct {
        pub fn hash(context: @This(), self: *const Self) u64 {
            _ = context;
            return self.hash;
        }
        pub fn eql(context: @This(), a: *const Self, b: *Self) bool {
            _ = context;
            if (a.hash != b.hash) {
                std.log.info("eql({}, {}) = {}", .{ a.*, b.*, false });
                return false;
            }

            // const result = std.mem.eql(u8, std.mem.sliceAsBytes(a.components.items), std.mem.sliceAsBytes(b.components.items));
            const result = std.meta.eql(a.components, b.components);
            std.log.info("eql({}, {}) = {}", .{ a.*, b.*, result });
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
                std.log.info("eql({}, {}) = {}", .{ a.*, b.archetype, false });
                return false;
            }

            // const result = std.mem.eql(u8, std.mem.sliceAsBytes(a.components.items), std.mem.sliceAsBytes(b.archetype.components.items));
            const result = std.meta.eql(a.components, b.archetype.components);
            std.log.info("eql({}, {}) = {}", .{ a.*, b.archetype, result });
            return result;
        }
    };

    pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "{{", .{});
        try std.fmt.format(writer, "{}", .{self.components});
        // for (self.components.items) |typeId, i| {
        //     if (i > 0) {
        //         try std.fmt.format(writer, ", ", .{});
        //     }
        //     try std.fmt.format(writer, "{}", .{typeId});
        // }
        try std.fmt.format(writer, "}} #{}", .{self.hash});
    }
};

pub fn hashTypes(types: []TypeId) u64 {
    var hash: u64 = 0;
    for (types) |id| {
        hash ^= id.hash;
    }
    return hash;
}

pub const World = struct {
    allocator: std.mem.Allocator,
    globalPool: std.heap.ArenaAllocator,

    archetypeTables: std.HashMap(*ArchetypeTable, *ArchetypeTable, ArchetypeTable.HashTableContext, 80),
    baseArchetypeTable: *ArchetypeTable,
    entities: std.AutoHashMap(u64, *ArchetypeTable),
    nextEntityId: u64 = 1,
    components: std.HashMap(TypeId, u64, TypeId.Context, 80),

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
        };

        // Create archetype table for empty entities.
        var archetype = try world.createArchetype(&.{});
        defer archetype.deinit();
        std.log.info("{}", .{archetype});
        world.baseArchetypeTable = try world.getOrCreateArchetypeTable(&archetype);

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

    pub fn createEntity(self: *Self) !u64 {
        _ = self;
        const entity = self.nextEntityId;
        self.nextEntityId += 1;
        std.log.info("createEntity {}", .{entity});

        try self.baseArchetypeTable.addEntity(entity, .{});
        try self.entities.put(entity, self.baseArchetypeTable);
        return entity;
    }

    pub fn createArchetype(self: *Self, components: []TypeId) !Archetype {
        // var list = try std.ArrayList(TypeId).initCapacity(self.allocator, components.len);
        // list.appendSliceAssumeCapacity(components);
        var hash = hashTypes(components);
        var bitSet = BitSet.initEmpty();
        for (components) |typeId| {
            bitSet.set(try self.getComponentId(typeId));
        }
        return Archetype.init(hash, bitSet);
    }

    pub fn createArchetypeTable(self: *Self, archetype: Archetype) !*ArchetypeTable {
        std.log.info("createArchetypeTable {}", .{archetype});
        var table = try self.globalPool.allocator().create(ArchetypeTable);
        table.* = try ArchetypeTable.init(archetype, self.allocator);
        try self.archetypeTables.put(table, table);
        return table;
    }

    pub fn getOrCreateArchetypeTable(self: *Self, archetype: *const Archetype) !*ArchetypeTable {
        std.log.info("getOrCreateArchetypeTable {}", .{archetype.*});
        if (self.archetypeTables.getKeyAdapted(archetype, Archetype.HashTableContext{})) |table| {
            std.log.info("reuse table {}", .{table.archetype});
            return table;
        } else {
            return try self.createArchetypeTable(try archetype.clone());
        }
    }

    pub fn getComponentId(self: *Self, typeId: TypeId) !u64 {
        if (self.components.get(typeId)) |componentId| {
            return componentId;
        } else {
            const componentId = self.components.count();
            try self.components.put(typeId, componentId);
            return componentId;
        }
    }

    // pub fn addComponentToArchetype(self: *Self, archetype: *const Archetype, component: i64) !void {}

    pub fn addComponent(self: *Self, entity: u64, component: anytype) !void {
        _ = self;
        _ = entity;
        _ = component;

        if (self.entities.get(entity)) |oldTable| {
            std.log.info("remove entity {} from table {}", .{ entity, oldTable });
            oldTable.removeEntity(entity);

            const typeId: TypeId = TypeId.init(@TypeOf(component));
            const componentId: u64 = try self.getComponentId(typeId);
            var newComponents = BitSet.initEmpty();
            newComponents.set(componentId);
            var newArchetype = try oldTable.archetype.addComponents(typeId.hash, newComponents);
            defer newArchetype.deinit();

            // @todo: get or create new table
            std.log.info("add entity {} to table {}", .{ entity, newArchetype });
            var newTable: *ArchetypeTable = try self.getOrCreateArchetypeTable(&newArchetype);
            try newTable.addEntity(entity, .{});

            try self.entities.put(entity, newTable);
        } else {
            return error.InvalidEntity;
        }
    }
};

pub fn Query(comptime Q: anytype) type {
    _ = Q;
    const Entity = struct {
        id: u64,
        position: *Position,
        gravity: *Gravity,
    };

    const Iterator = struct {
        const Self = @This();

        pub fn next(self: *Self) ?Entity {
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
    try world.addComponent(entity, Position{ .position = .{ 1, 2, 3 } });
    world.dump();
    try world.addComponent(entity, Gravity{});
    world.dump();

    const entity2 = try world.createEntity();
    world.dump();
    try world.addComponent(entity2, Position{ .position = .{ 4, 5, 6 } });
    world.dump();
    try world.addComponent(entity2, Gravity{});
    world.dump();
    try world.addComponent(entity2, 5);
    world.dump();
    try world.addComponent(entity2, true);
    world.dump();

    try world.addComponent(entity, false);
    world.dump();
    try world.addComponent(entity, 69);
    world.dump();

    world.addSystem(testSystem);

    world.dump();
}
