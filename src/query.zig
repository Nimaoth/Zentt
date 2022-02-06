const std = @import("std");

const ArchetypeTable = @import("archetype_table.zig");
const Chunk = @import("chunk.zig");
const Rtti = @import("rtti.zig");
const SystemParameterType = @import("system_parameter_type.zig").SystemParameterType;

pub const EntityId = u64;
pub const ComponentId = u64;

pub fn Query(comptime Components: anytype) type {
    const EntityHandle = getEntityHandle(Components);

    const Iterator = struct {
        const Self = @This();

        tables: []*ArchetypeTable,
        tableIndex: u64 = 0,
        currentChunk: ?*Chunk,
        entityIndex: u64 = 0,
        componentIndexMap: [getNumSizedTypes(Components)]u64 = undefined,

        pub fn init(tables: []*ArchetypeTable) @This() {
            var result = @This(){
                .tables = tables,
                .currentChunk = if (tables.len > 0) tables[0].firstChunk else null,
            };
            if (result.tables.len > 0) {
                result.updateComponentIndexMap();
            }
            return result;
        }

        pub fn updateComponentIndexMap(self: *Self) void {
            std.debug.assert(self.tableIndex < self.tables.len);
            const typeInfo = @typeInfo(@TypeOf(Components)).Struct;
            var index: u64 = 0;

            const table = self.tables[self.tableIndex];

            inline for (typeInfo.fields) |field| {
                const ComponentType = field.default_value orelse unreachable;
                if (@sizeOf(ComponentType) > 0) {
                    self.componentIndexMap[index] = table.getListIndexForType(Rtti.init(ComponentType));
                    index += 1;
                }
            }
        }

        pub fn mapComponentIndex(self: *const Self, index: u64) u64 {
            return self.componentIndexMap[index];
        }

        pub fn next(self: *Self) ?EntityHandle {
            if (self.tableIndex >= self.tables.len) {
                return null;
            }

            if (self.entityIndex >= self.currentChunk.?.count) {
                self.entityIndex = 0;
                self.currentChunk = self.currentChunk.?.next;
                while (true) {
                    if (self.currentChunk != null and self.currentChunk.?.count == 0) {
                        self.currentChunk = self.currentChunk.?.next;
                    } else if (self.currentChunk == null) {
                        // reached end of chunk list, go to next table
                        self.tableIndex += 1;
                        if (self.tableIndex < self.tables.len) {
                            self.currentChunk = self.tables[self.tableIndex].firstChunk;
                            self.updateComponentIndexMap();
                        } else {
                            // reached end of last table, done
                            return null;
                        }
                    } else {
                        break;
                    }
                }
            }

            std.debug.assert(self.currentChunk != null);
            std.debug.assert(self.entityIndex < self.currentChunk.?.count);

            const chunk: *Chunk = self.currentChunk orelse unreachable;
            const index = self.entityIndex;
            self.entityIndex += 1;

            var result: EntityHandle = undefined;
            result.id = chunk.getEntityId(index);

            const typeInfo = @typeInfo(@TypeOf(Components)).Struct;
            var componentIndex: u64 = 0;
            inline for (typeInfo.fields) |field| {
                const ComponentType = field.default_value orelse unreachable;
                std.debug.assert(@TypeOf(ComponentType) == type);
                if (@sizeOf(ComponentType) > 0) {
                    var data = chunk.getComponentRaw(self.mapComponentIndex(componentIndex), index);

                    @field(result, @typeName(ComponentType)) = @ptrCast(*ComponentType, @alignCast(@alignOf(ComponentType), data.ptr));
                    componentIndex += 1;
                }
            }

            return result;
        }
    };

    const QueryTemplate = struct {
        const Self = @This();
        pub const Type = SystemParameterType.Query;
        pub const ComponentTypes = Components;
        pub const ComponentCount = @typeInfo(@TypeOf(Components)).Struct.fields.len;

        tables: []*ArchetypeTable,
        enabled: bool,
        componentCount: i64 = ComponentCount,

        pub fn init(tables: []*ArchetypeTable, enabled: bool) @This() {
            return @This(){
                .tables = tables,
                .enabled = enabled,
            };
        }

        pub fn iter(self: *const Self) Iterator {
            return Iterator.init(self.tables);
        }
    };

    return QueryTemplate;
}

fn getNumSizedTypes(comptime T: anytype) u64 {
    const typeInfo = @typeInfo(@TypeOf(T)).Struct;
    var num: u64 = 0;
    inline for (typeInfo.fields) |field| {
        const ComponentType = field.default_value orelse unreachable;
        if (@sizeOf(ComponentType) > 0) {
            num += 1;
        }
    }
    return num;
}

fn getEntityHandle(comptime Components: anytype) type {
    _ = Components;
    const typeInfo = comptime blk: {
        const T = @TypeOf(Components);
        const typeInfo = @typeInfo(T).Struct;

        // Count fields with non-zero size
        const fieldsWithSize: u64 = getNumSizedTypes(Components);

        var fields: [fieldsWithSize + 1]std.builtin.TypeInfo.StructField = undefined;

        fields[0] = .{
            .name = "id",
            .field_type = EntityId,
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
                    .field_type = *ComponentType,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(*ComponentType),
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
