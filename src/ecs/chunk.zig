const std = @import("std");

const Rtti = @import("../util/rtti.zig");
const ArchetypeTable = @import("archetype_table.zig");
const Chunk = @import("chunk.zig");
const Entity = @import("entity.zig");
const EntityRef = Entity.Ref;

pub const EntityId = Entity.Id;
pub const ComponentId = u64;

const Self = @This();

pub const Components = struct {
    componentType: Rtti.TypeId,
    data: []u8,

    pub inline fn getRaw(self: *const @This(), index: u64) []u8 {
        const byteIndex = index * self.componentType.typeInfo.size;
        return self.data[byteIndex..(byteIndex + self.componentType.typeInfo.size)];
    }

    pub fn setRaw(self: *@This(), index: u64, data: []const u8) void {
        var target = self.getRaw(index);
        std.debug.assert(target.len == data.len);
        std.mem.copy(u8, target, data);
    }
};

allocator: std.mem.Allocator,
pool: []u8,

capacity: u64,
count: u64 = 0,

entity_refs: []EntityRef,

/// Contains data about non zero sized components.
/// To get all components you have to go through table.archetype.components
components_offset: usize,
components: []Components,

table: *ArchetypeTable,
next: ?*Chunk = null,

pub fn init(table: *ArchetypeTable, capacity: u64, allocator: std.mem.Allocator) !*@This() {
    var size: u64 = @sizeOf(Self);

    // [N]Components
    const numComponents = table.archetype.components.bitSet.count();
    const componentsSize = numComponents * @sizeOf(Components);
    size = std.mem.alignForward(size, @alignOf(Components));
    const componentsIndex = size;
    size += componentsSize;

    // entity ids
    const entityIdsSize = capacity * @sizeOf(EntityRef);
    size = std.mem.alignForward(size, @alignOf(EntityRef));
    const entityIdsIndex = size;
    size += entityIdsSize;

    // components
    size = std.mem.alignForward(size, 64);
    const componentDataIndex = size;
    var iter = table.archetype.components.iterator();
    while (iter.next()) |componentId| {
        const componentType = table.archetype.world.getComponentType(componentId) orelse unreachable;
        if (componentType.typeInfo.size == 0)
            continue;

        size = std.mem.alignForward(size, componentType.typeInfo.alignment) + capacity * componentType.typeInfo.size + 8;
    }

    const pool = try allocator.alignedAlloc(u8, 4096, size);

    //
    var entity_refs = std.mem.bytesAsSlice(EntityRef, pool[entityIdsIndex..(entityIdsIndex + entityIdsSize)]);
    std.mem.set(EntityRef, entity_refs, .{});

    // Fill components array
    var components = std.mem.bytesAsSlice(Components, pool[componentsIndex..(componentsIndex + componentsSize)]);
    var componentIndex: u64 = 0;
    var currentComponentDataIndex = componentDataIndex;
    iter = table.archetype.components.iterator();
    while (iter.next()) |componentId| {
        const componentType = table.archetype.world.getComponentType(componentId) orelse unreachable;
        if (componentType.typeInfo.size == 0)
            continue;
        defer componentIndex += 1;

        currentComponentDataIndex = std.mem.alignForward(currentComponentDataIndex, componentType.typeInfo.alignment);
        components[componentIndex] = Components{
            .componentType = componentType,
            .data = pool[currentComponentDataIndex..(currentComponentDataIndex + capacity * componentType.typeInfo.size)],
        };
        std.mem.set(u8, components[componentIndex].data, @intCast(u8, componentIndex + 1));
        currentComponentDataIndex += capacity * componentType.typeInfo.size + 8;
    }
    components = components[0..componentIndex];

    var result = @ptrCast(*Self, pool.ptr);
    result.* = @This(){
        .allocator = allocator,
        .pool = pool,
        .capacity = capacity,
        .entity_refs = entity_refs,
        .components_offset = componentsIndex,
        .components = components,
        .table = table,
    };

    return result;
}

pub fn deinit(self: *const Self) ?*Self {
    const next = self.next;
    const pool = self.pool;
    const allocator = self.allocator;
    allocator.free(pool);
    return next;
}

pub fn isFull(self: *const Self) bool {
    return self.count >= self.capacity;
}

pub fn getOrCreateNext(self: *Self) !*Self {
    if (self.next) |n| {
        return n;
    }
    self.next = try Self.init(self.table, self.capacity * 2, self.allocator);
    return self.next.?;
}

pub inline fn getComponents(self: *const Self, componentIndex: u64) *Components {
    return &self.components[componentIndex];
}

pub fn getEntityRef(self: *Self, index: u64) EntityRef {
    std.debug.assert(index < self.count);
    return self.entity_refs[index];
}

pub inline fn getComponentRaw(self: *Self, componentIndex: u64, dataIndex: u64) []u8 {
    std.debug.assert(dataIndex < self.count);
    const components = self.getComponents(componentIndex);
    return components.getRaw(dataIndex);
}

pub fn addEntity(self: *Self, entity: *Entity) !void {
    var chunk = self;
    while (chunk.isFull()) {
        chunk = try chunk.getOrCreateNext();
    }

    entity.chunk = chunk;
    entity.index = chunk.count;

    chunk.entity_refs[entity.index] = .{ .id = entity.id, .entity = entity };
    chunk.count += 1;
}

pub fn setComponentRaw(self: *Self, componentIndex: u64, dataIndex: u64, data: []const u8) !void {
    std.debug.assert(dataIndex < self.count);
    var components = self.getComponents(componentIndex);
    components.setRaw(dataIndex, data);
}

pub fn removeEntity(self: *Self, index: u64) void {
    std.debug.assert(index < self.count);

    self.table.updateFirstFreeChunk(self);

    self.count -= 1;
    if (index < self.count) {
        self.entity_refs[index] = self.entity_refs[self.count];
        self.entity_refs[self.count] = .{ .id = 0, .entity = undefined };

        for (self.components) |*componentList| {
            var source = componentList.getRaw(self.count);
            var target = componentList.getRaw(index);
            std.mem.copy(u8, target, source);
        }

        self.entity_refs[index].entity.index = index;
    }
}
