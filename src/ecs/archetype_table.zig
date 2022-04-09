const std = @import("std");

const Archetype = @import("archetype.zig");
const Chunk = @import("chunk.zig");
const Entity = @import("entity.zig");
const EntityRef = Entity.Ref;

const BitSet = @import("../util/bit_set.zig");
const Rtti = @import("../util/rtti.zig");

typeToList: std.AutoHashMap(Rtti.TypeId, u64),
supersets: std.AutoHashMap(BitSet, *Self),
subsets: std.AutoHashMap(BitSet, *Self),
archetype: Archetype,

firstChunk: *Chunk,
firstFreeChunk: ?*Chunk = null,

const Self = @This();

pub fn init(self: *Self, archetype: Archetype, allocator: std.mem.Allocator) !void {
    self.* = Self{
        .supersets = std.AutoHashMap(BitSet, *Self).init(allocator),
        .subsets = std.AutoHashMap(BitSet, *Self).init(allocator),
        .archetype = archetype,
        .firstChunk = try Chunk.init(self, 100, allocator),
        .typeToList = std.AutoHashMap(Rtti.TypeId, u64).init(allocator),
    };
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

pub fn getListIndexForType(self: *const Self, rtti: Rtti.TypeId) ?u64 {
    return self.typeToList.get(rtti);
}

pub fn updateFirstFreeChunk(self: *Self, chunk: *Chunk) void {
    // @todo @note: using capacity to check if chunk comes before self.firstFreeChunk
    // only works because right now each chunk has increased capacity.
    if (self.firstFreeChunk == null or chunk.capacity < self.firstFreeChunk.?.capacity) {
        self.firstFreeChunk = chunk;
    }
}

pub fn getNextFreeChunk(self: *Self) !*Chunk {
    if (self.firstFreeChunk == null)
        self.firstFreeChunk = self.firstChunk;

    var chunk = self.firstFreeChunk.?;
    while (chunk.isFull()) {
        chunk = try chunk.getOrCreateNext();
    }

    self.firstFreeChunk = chunk;
    return chunk;
}

pub fn getEntityCount(self: *const Self) usize {
    var count: usize = 0;
    var chunk: ?*Chunk = self.firstChunk;

    while (chunk) |c| {
        count += c.count;
        chunk = c.next;
    }

    return count;
}

pub fn addEntity(self: *Self, entity: *Entity, components: anytype) !void {
    // @todo: check if the provided components match the archetype
    var free_chunk = try self.getNextFreeChunk();
    try free_chunk.addEntity(entity);

    const ComponentsType = if (@typeInfo(@TypeOf(components)) == .Pointer) std.meta.Child(@TypeOf(components)) else @TypeOf(components);

    inline for (@typeInfo(ComponentsType).Struct.fields) |field| {
        const componentType = Rtti.typeId(field.field_type);
        const index = self.getListIndexForType(componentType) orelse unreachable;
        try entity.chunk.setComponentRaw(index, entity.index, std.mem.asBytes(&@field(components, field.name)));
    }
}

pub fn addEntityRaw(self: *Self, entity: *Entity, component_types: []const Rtti.TypeId, component_data: []const []const u8) !void {
    // @todo: check if the provided components match the archetype
    std.debug.assert(component_types.len == component_data.len);
    var free_chunk = try self.getNextFreeChunk();
    try free_chunk.addEntity(entity);

    for (component_types) |component_type, i| {
        if (component_type.typeInfo.size > 0) {
            const index = self.getListIndexForType(component_type) orelse unreachable;
            try entity.chunk.setComponentRaw(index, entity.index, component_data[i]);
        }
    }
}

pub fn copyEntityWithComponentIntoRaw(self: *Self, entity: *Entity, componentType: Rtti.TypeId, componentData: []const u8) !void {
    // @todo: check if the provided components match the archetype

    const old_entity = entity.*;

    // Add entity
    var free_chunk = try self.getNextFreeChunk();
    try free_chunk.addEntity(entity);

    // Add new component
    std.debug.assert(self.typeToList.count() == entity.chunk.components.len);
    if (componentType.typeInfo.size > 0) {
        try entity.chunk.setComponentRaw(self.getListIndexForType(componentType) orelse unreachable, entity.index, componentData);
    }

    // Copy existing components
    for (old_entity.chunk.components) |*componentList| {
        var oldData = componentList.getRaw(old_entity.index);
        const newComponentIndex = self.getListIndexForType(componentList.componentType) orelse unreachable;
        try entity.chunk.setComponentRaw(newComponentIndex, entity.index, oldData);
    }
}

pub fn copyEntityIntoRaw(self: *Self, entity: *Entity) !void {
    // @todo: check if the provided components match the archetype

    const old_entity = entity.*;

    // Add entity
    var free_chunk = try self.getNextFreeChunk();
    try free_chunk.addEntity(entity);

    // Copy existing components
    for (old_entity.chunk.components) |*component_list| {
        if (self.getListIndexForType(component_list.componentType)) |index| {
            var old_data = component_list.getRaw(old_entity.index);
            try entity.chunk.setComponentRaw(index, entity.index, old_data);
        }
    }
}

pub fn copyEntityWithComponentInto(self: *Self, entity: *Entity, newComponent: anytype) !void {
    // @todo: check if the provided components match the archetype

    const ComponentType = @TypeOf(newComponent);

    const old_entity = entity.*;

    // Add entity
    try self.firstChunk.addEntity(entity);

    // Add new component
    const componentType = Rtti.typeId(ComponentType);
    std.debug.assert(self.typeToList.count() == entity.chunk.components.len);
    if (componentType.size > 0) {
        try entity.chunk.setComponentRaw(self.getListIndexForType(componentType), entity.index, std.mem.asBytes(&newComponent)) orelse unreachable;
    }

    // Copy existing components
    for (old_entity.chunk.components) |*componentList| {
        var oldData = componentList.getRaw(old_entity.index);
        const newComponentIndex = entity.chunk.table.getListIndexForType(componentList.componentType) orelse unreachable;
        try entity.chunk.setComponentRaw(newComponentIndex, entity.index, oldData);
    }
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
