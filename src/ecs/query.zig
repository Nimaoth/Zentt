const std = @import("std");

const ArchetypeTable = @import("archetype_table.zig");
const Chunk = @import("chunk.zig");
const SystemParameterType = @import("system_parameter_type.zig").SystemParameterType;

const Rtti = @import("../util/rtti.zig");

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

            const table = self.tables[self.tableIndex];

            inline for (typeInfo.fields) |field, index| {
                const ComponentType = field.default_value orelse unreachable;
                if (@sizeOf(ComponentType) > 0) {
                    self.componentIndexMap[index] = table.getListIndexForType(Rtti.typeId(ComponentType)) orelse unreachable;
                } else {
                    self.componentIndexMap[index] = 0;
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
            const resultTypeInfo = @typeInfo(EntityHandle).Struct;
            inline for (typeInfo.fields) |field, i| {
                const ComponentType = field.default_value orelse unreachable;
                std.debug.assert(@TypeOf(ComponentType) == type);
                if (@sizeOf(ComponentType) > 0) {
                    var data = chunk.getComponentRaw(self.mapComponentIndex(i), index);
                    @field(result, resultTypeInfo.fields[i + 1].name) = @ptrCast(*ComponentType, @alignCast(@alignOf(ComponentType), data.ptr));
                } else {
                    @field(result, resultTypeInfo.fields[i + 1].name) = 0;
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
    return typeInfo.fields.len;
}

fn deduplicate(comptime name: []const u8, comptime otherFields: []std.builtin.TypeInfo.StructField) []const u8 {
    for (otherFields) |field| {
        if (std.mem.eql(u8, name, field.name)) {
            return deduplicate(name ++ "2", otherFields);
        }
    }
    return name;
}

fn getEntityHandle(comptime Components: anytype) type {
    _ = Components;
    const typeInfo = comptime blk: {
        const T = @TypeOf(Components);
        const typeInfo = @typeInfo(T).Struct;

        var fields: [typeInfo.fields.len + 1]std.builtin.TypeInfo.StructField = undefined;

        fields[0] = .{
            .name = "id",
            .field_type = EntityId,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf([]u64),
        };

        // Fill field type info for all components with non-zero size
        inline for (typeInfo.fields) |field, index| {
            const ComponentType = field.default_value orelse unreachable;

            std.debug.assert(@TypeOf(ComponentType) == type);
            if (@sizeOf(ComponentType) > 0) {
                fields[index + 1] = .{
                    .name = deduplicate(@typeName(ComponentType), fields[0..(index + 1)]),
                    .field_type = *ComponentType,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(*ComponentType),
                };
            } else {
                fields[index + 1] = .{
                    .name = deduplicate(@typeName(ComponentType), fields[0..(index + 1)]),
                    .field_type = u8,
                    .default_value = @intCast(u8, 0),
                    .is_comptime = false,
                    .alignment = @alignOf(u8),
                };
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
