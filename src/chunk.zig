const std = @import("std");

const ArchetypeTable = @import("archetype_table.zig");
const Chunk = @import("chunk.zig");
const Rtti = @import("rtti.zig");
const Entity = @import("entity.zig");

pub const EntityId = u64;
pub const ComponentId = u64;

const Self = @This();

const Components = struct {
    componentType: Rtti,
    data: []u8,

    pub fn getRaw(self: *const @This(), index: u64) []u8 {
        const byteIndex = index * self.componentType.size;
        return self.data[byteIndex..(byteIndex + self.componentType.size)];
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

entityIds: []EntityId,
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
    const entityIdsSize = capacity * @sizeOf(EntityId);
    size = std.mem.alignForward(size, @alignOf(EntityId));
    const entityIdsIndex = size;
    size += entityIdsSize;

    // components
    size = std.mem.alignForward(size, 64);
    const componentDataIndex = size;
    var iter = table.archetype.components.iterator();
    while (iter.next()) |componentId| {
        const componentType = table.archetype.world.getComponentType(componentId) orelse unreachable;
        if (componentType.size == 0)
            continue;

        size = std.mem.alignForward(size, componentType.alignment) + capacity * componentType.size + 8;
    }

    const pool = try allocator.alignedAlloc(u8, 4096, size);

    //
    var entityIds = std.mem.bytesAsSlice(EntityId, pool[entityIdsIndex..(entityIdsIndex + entityIdsSize)]);
    std.mem.set(u64, entityIds, 0);

    // Fill components array
    var components = std.mem.bytesAsSlice(Components, pool[componentsIndex..(componentsIndex + componentsSize)]);
    var componentIndex: u64 = 0;
    var currentComponentDataIndex = componentDataIndex;
    iter = table.archetype.components.iterator();
    while (iter.next()) |componentId| {
        const componentType = table.archetype.world.getComponentType(componentId) orelse unreachable;
        if (componentType.size == 0)
            continue;
        defer componentIndex += 1;

        currentComponentDataIndex = std.mem.alignForward(currentComponentDataIndex, componentType.alignment);
        components[componentIndex] = Components{
            .componentType = componentType,
            .data = pool[currentComponentDataIndex..(currentComponentDataIndex + capacity * componentType.size)],
        };
        std.mem.set(u8, components[componentIndex].data, @intCast(u8, componentIndex + 1));
        currentComponentDataIndex += capacity * componentType.size + 8;
    }
    components = components[0..componentIndex];

    var result = @ptrCast(*Self, pool.ptr);
    result.* = @This(){
        .allocator = allocator,
        .pool = pool,
        .capacity = capacity,
        .entityIds = entityIds,
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
    self.next = try Self.init(self.table, self.capacity, self.allocator);
    return self.next.?;
}

pub fn getComponents(self: *const Self, componentIndex: u64) *Components {
    return &self.components[componentIndex];
}

pub fn getEntityId(self: *Self, index: u64) u64 {
    std.debug.assert(index < self.count);
    return self.entityIds[index];
}

pub fn getComponentRaw(self: *Self, componentIndex: u64, dataIndex: u64) []u8 {
    std.debug.assert(dataIndex < self.count);
    const components = self.getComponents(componentIndex);
    return components.getRaw(dataIndex);
}

pub fn addEntity(self: *Self, entityId: EntityId) !Entity {
    var chunk = self;
    while (chunk.isFull()) {
        chunk = try chunk.getOrCreateNext();
    }

    const index = chunk.count;
    self.entityIds[index] = entityId;
    chunk.count += 1;
    return Entity{ .id = entityId, .chunk = chunk, .index = index };
}

pub fn setComponentRaw(self: *Self, componentIndex: u64, dataIndex: u64, data: []const u8) !void {
    std.debug.assert(dataIndex < self.count);
    var components = self.getComponents(componentIndex);
    components.setRaw(dataIndex, data);
}

pub const EntityIndexUpdate = struct { entityId: u64, newIndex: u64 };

pub fn removeEntity(self: *Self, index: u64) ?EntityIndexUpdate {
    std.debug.assert(index < self.count);

    self.count -= 1;
    if (index < self.count) {
        self.entityIds[index] = self.entityIds[self.count];
        self.entityIds[self.count] = 0;

        for (self.components) |*componentList| {
            var source = componentList.getRaw(self.count);
            var target = componentList.getRaw(index);
            std.mem.copy(u8, target, source);
        }

        // The index of the last entity changed because it was moved to the current index i.
        // Update the index stored in the entities map in the world.
        return EntityIndexUpdate{ .entityId = self.entityIds[index], .newIndex = index };
    }
    return null;
}
