const std = @import("std");

const Archetype = @import("archetype.zig");
const BitSet = @import("bit_set.zig");
const Rtti = @import("rtti.zig");
const Chunk = @import("chunk.zig");
const Entity = @import("entity.zig");

typeToList: std.AutoHashMap(Rtti.TypeId, u64),
supersets: std.AutoHashMap(BitSet, *Self),
subsets: std.AutoHashMap(BitSet, *Self),
archetype: Archetype,

firstChunk: *Chunk,

const Self = @This();

pub fn init(self: *Self, archetype: Archetype, allocator: std.mem.Allocator) !void {
    self.supersets = std.AutoHashMap(BitSet, *Self).init(allocator);
    self.subsets = std.AutoHashMap(BitSet, *Self).init(allocator);
    self.archetype = archetype;
    self.firstChunk = try Chunk.init(self, 100, allocator);
    self.typeToList = std.AutoHashMap(Rtti.TypeId, u64).init(allocator);
    var iter = archetype.components.iterator();
    while (iter.next()) |componentId| {
        const componentType = archetype.world.getComponentType(componentId) orelse unreachable;
        if (componentType.typeInfo.size > 0) {
            try self.typeToList.put(componentType, self.typeToList.count());
        }
    }
}

pub fn deinit(self: *Self) void {
    var chunk: ?*Chunk = self.firstChunk;
    while (chunk) |c| {
        chunk = c.deinit();
    }
    self.typeToList.deinit();
    self.supersets.deinit();
    self.subsets.deinit();
}

pub fn getListIndexForType(self: *const Self, rtti: Rtti.TypeId) u64 {
    return self.typeToList.get(rtti) orelse unreachable;
}

// pub fn getTyped(self: *Self, comptime Components: anytype) getType(Components) {
//     _ = self;
//     const T = @TypeOf(Components);
//     const typeInfo = @typeInfo(T).Struct;

//     var result: getType(Components) = undefined;

//     result.entities = self.entities.items;
//     inline for (typeInfo.fields) |field| {
//         const ComponentType = field.default_value orelse unreachable;
//         std.debug.assert(@TypeOf(ComponentType) == type);

//         const componentType = Rtti.init(ComponentType);
//         const componentId = self.archetype.world.getComponentId(componentType) catch unreachable;

//         if (self.getListForType(componentType)) |componentList| {
//             std.debug.assert(componentList.componentId == componentId);
//             @field(result, @typeName(ComponentType)) = std.mem.bytesAsSlice(ComponentType, componentList.data.items);
//         }
//     }

//     return result;
//     // return Archetype.init(self, hash, bitSet);
// }

pub fn removeEntity(self: *Self, entity: Entity) ?Chunk.EntityIndexUpdate {
    std.debug.assert(entity.chunk.table == self);
    return entity.chunk.removeEntity(entity.index);
}

pub fn addEntity(self: *Self, entityId: u64, components: anytype) !Entity {
    // @todo: check if the provided components match the archetype

    std.log.info("addEntity({}): {}", .{ entityId, components });
    const entity: Entity = try self.firstChunk.addEntity(entityId);

    const typeInfo = @typeInfo(@TypeOf(components)).Struct;
    inline for (typeInfo.fields) |field| {
        const componentType = Rtti.typeId(field.field_type);
        const index = self.getListIndexForType(componentType);
        try entity.chunk.setComponentRaw(index, entity.index, std.mem.asBytes(&@field(components, field.name)));
    }

    return entity;
}

pub fn copyEntityIntoRaw(self: *Self, entity: Entity, componentType: Rtti.TypeId, componentData: []const u8) !Entity {
    // @todo: check if the provided components match the archetype
    std.log.err("ArchetypeTable.copyEntityIntoRaw: {any}", .{componentData});

    std.log.info("copyEntityIntoRaw({}): {}", .{ entity, componentType });

    // Add entity
    const newEntity: Entity = try self.firstChunk.addEntity(entity.id);

    // Add new component
    std.debug.assert(self.typeToList.count() == newEntity.chunk.components.len);
    if (componentType.typeInfo.size > 0) {
        try newEntity.chunk.setComponentRaw(self.getListIndexForType(componentType), newEntity.index, componentData);
    }

    // Copy existing components
    for (entity.chunk.components) |*componentList| {
        var oldData = componentList.getRaw(entity.index);
        const newComponentIndex = newEntity.chunk.table.getListIndexForType(componentList.componentType);
        try newEntity.chunk.setComponentRaw(newComponentIndex, newEntity.index, oldData);
    }

    return newEntity;
}

pub fn copyEntityInto(self: *Self, entity: Entity, newComponent: anytype) !Entity {
    // @todo: check if the provided components match the archetype

    const ComponentType = @TypeOf(newComponent);

    std.log.info("copyEntityInto({}): {}", .{ entity, newComponent });

    // Add entity
    const newEntity: Entity = try self.firstChunk.addEntity(entity.id);

    // Add new component
    const componentType = Rtti.typeId(ComponentType);
    std.debug.assert(self.typeToList.count() == newEntity.chunk.components.len);
    if (componentType.size > 0) {
        try newEntity.chunk.setComponentRaw(self.getListIndexForType(componentType), newEntity.index, std.mem.asBytes(&newComponent));
    }

    // Copy existing components
    for (entity.chunk.components) |*componentList| {
        var oldData = componentList.getRaw(entity.index);
        const newComponentIndex = newEntity.chunk.table.getListIndexForType(componentList.componentType);
        try newEntity.chunk.setComponentRaw(newComponentIndex, newEntity.index, oldData);
    }

    return newEntity;
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
