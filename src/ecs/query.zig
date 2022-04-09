const std = @import("std");

const ArchetypeTable = @import("archetype_table.zig");
const Chunk = @import("chunk.zig");
const World = @import("world.zig");
const SystemParameterType = @import("system_parameter_type.zig").SystemParameterType;

const Rtti = @import("../util/rtti.zig");

const Entity = @import("entity.zig");
const EntityId = Entity.EntityId;
const EntityRef = Entity.Ref;

pub const ComponentId = u64;

const root = @import("root");

pub const track_iter_invalidation: bool = if (@hasDecl(root, "query_track_iter_invalidation")) root.query_track_iter_invalidation else false;

pub fn Query(comptime Components: anytype) type {
    const EntityHandle = getEntityHandle(Components);
    const ComponentSlices = getEntityHandles(Components);

    const Iterator = struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        free_chunks: bool,

        world: *World,
        version: u128,

        chunks: []*Chunk,
        chunk_index: usize = 0,
        entity_index: u64 = 0,

        entity_handles: ComponentSlices = std.mem.zeroes(ComponentSlices),
        current_entity: EntityHandle = undefined,

        pub fn init(allocator: std.mem.Allocator, chunks: []*Chunk, free_chunks: bool, world: *World) @This() {
            var result = @This(){
                .allocator = allocator,
                .free_chunks = free_chunks,
                .chunks = chunks,
                .world = world,
                .version = world.version,
            };

            if (result.chunks.len > 0) {
                result.updateForCurrentChunk();
            }

            return result;
        }

        pub fn deinit(self: *const Self) void {
            if (self.free_chunks) {
                self.allocator.free(self.chunks);
            }
        }

        pub fn updateForCurrentChunk(self: *Self) void {
            const chunk = self.chunks[self.chunk_index];
            const typeInfo = @typeInfo(@TypeOf(Components)).Struct;
            const resultTypeInfo = @typeInfo(EntityHandle).Struct;

            self.entity_handles.ref = chunk.entity_refs[0..chunk.count];

            inline for (typeInfo.fields) |field, i| {
                const ComponentType = field.default_value orelse unreachable;
                std.debug.assert(@TypeOf(ComponentType) == type);
                if (@sizeOf(ComponentType) > 0) {
                    const component_index = chunk.table.getListIndexForType(Rtti.typeId(ComponentType)) orelse unreachable;
                    const components = std.mem.bytesAsSlice(ComponentType, @alignCast(@alignOf(ComponentType), chunk.getComponents(component_index).data));
                    @field(self.entity_handles, resultTypeInfo.fields[i + 1].name) = components[0..chunk.count];
                }
            }
        }

        pub fn count(self: *const Self) usize {
            var result: usize = 0;
            for (self.chunks) |chunk| {
                result += chunk.count;
            }
            return result;
        }

        pub inline fn next(self: *Self) ?*EntityHandle {
            if (comptime track_iter_invalidation) {
                if (self.world.version != self.version) {
                    std.log.err("Query Iterator was invalidated. (Created at {}, world at {})", .{ self.version, self.world.version });
                    @panic("Query Iterator was invalidated");
                }
            }

            if (self.entity_index >= self.entity_handles.ref.len) {
                if (self.chunk_index + 1 >= self.chunks.len)
                    return null;

                self.entity_index = 0;
                self.chunk_index += 1;
                self.updateForCurrentChunk();
            }

            self.current_entity.ref = &self.entity_handles.ref[self.entity_index];

            const typeInfo = @typeInfo(@TypeOf(Components)).Struct;
            const resultTypeInfo = @typeInfo(EntityHandle).Struct;
            inline for (typeInfo.fields) |field, i| {
                const field_name = resultTypeInfo.fields[i + 1].name;
                const ComponentType = field.default_value orelse unreachable;
                if (@sizeOf(ComponentType) > 0) {
                    @field(self.current_entity, field_name) = &@field(self.entity_handles, field_name)[self.entity_index];
                }
            }

            self.entity_index += 1;

            return &self.current_entity;
        }
    };

    const QueryTemplate = struct {
        const Self = @This();
        pub const Type = SystemParameterType.Query;
        pub const ComponentTypes = Components;
        pub const ComponentCount = @typeInfo(@TypeOf(Components)).Struct.fields.len;
        pub const EntityHandle = EntityHandle;
        pub const Iterator = Iterator;

        allocator: std.mem.Allocator,
        world: *World,
        chunks: []*Chunk,
        free_chunks: bool,
        componentCount: i64 = ComponentCount,

        pub fn init(allocator: std.mem.Allocator, world: *World, chunks: []*Chunk, free_chunks: bool) @This() {
            return @This(){
                .allocator = allocator,
                .world = world,
                .chunks = chunks,
                .free_chunks = free_chunks,
            };
        }

        pub fn deinit(self: *const Self) void {
            if (self.free_chunks) {
                self.allocator.free(self.chunks);
            }
        }

        pub fn iter(self: *const Self) Iterator {
            return Iterator.init(self.allocator, self.chunks, false, self.world);
        }

        pub fn iterOwned(self: *const Self) Iterator {
            return Iterator.init(self.allocator, self.chunks, true, self.world);
        }

        // Returns the number of entities which match this query.
        pub fn count(self: *const Self) u64 {
            var result: u64 = 0;
            for (self.chunks) |chunk| {
                result += chunk.count;
            }
            return result;
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

fn isLowerCase(c: u8) bool {
    return c >= 'a' and c <= 'z';
}

fn isUpperCase(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn toLowerCase(c: u8) u8 {
    if (isUpperCase(c)) return (c - 'A') + 'a';
    return c;
}

/// Converts from "PascalCase" to "sake_case", and removes "Component" suffix if present.
fn componentNameToFieldName(comptime name: []const u8) []const u8 {
    // Count how many _ we have to insert. (underscore between lower case letter followed by upper case letter)
    comptime var underscore_count = 0;
    comptime var last = name[0];
    inline for (name[1..]) |current| {
        if (isLowerCase(last) and isUpperCase(current)) {
            underscore_count += 1;
        }
        last = current;
    }

    comptime var buffer: [name.len + underscore_count]u8 = [1]u8{toLowerCase(name[0])} ** (name.len + underscore_count);

    comptime var index = 1;
    last = name[0];
    inline for (name[1..]) |current| {
        if (isLowerCase(last) and isUpperCase(current)) {
            buffer[index] = '_';
            index += 1;
            buffer[index] = toLowerCase(current);
        } else {
            buffer[index] = toLowerCase(current);
        }
        last = current;
        index += 1;
    }

    // const T = @Type(std.builtin.TypeInfo{ .Struct = .{ .layout = .Extern, .fields = &.{.{ .name = buffer[0..], .field_type = u8, .default_value = @intCast(u8, 0), .is_comptime = false, .alignment = 1 }}, .decls = &.{}, .is_tuple = false } });
    // @compileLog(@typeInfo(T).Struct.fields[0].name);

    if (std.mem.endsWith(u8, buffer[0..], "_component")) {
        return buffer[0..(buffer.len - "_component".len)];
    }

    return buffer[0..];
}

fn getEntityHandles(comptime Components: anytype) type {
    _ = Components;
    const typeInfo = comptime blk: {
        const T = @TypeOf(Components);
        const typeInfo = @typeInfo(T).Struct;

        var fields: [typeInfo.fields.len + 1]std.builtin.TypeInfo.StructField = undefined;

        fields[0] = .{
            .name = "ref",
            .field_type = []const EntityRef,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf([]const EntityRef),
        };

        // Fill field type info for all components with non-zero size
        inline for (typeInfo.fields) |field, index| {
            const ComponentType = field.default_value orelse unreachable;

            std.debug.assert(@TypeOf(ComponentType) == type);
            if (@sizeOf(ComponentType) > 0) {
                fields[index + 1] = .{
                    .name = componentNameToFieldName(deduplicate(@typeName(ComponentType), fields[0..(index + 1)])),
                    .field_type = []ComponentType,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(*ComponentType),
                };
            } else {
                fields[index + 1] = .{
                    .name = componentNameToFieldName(deduplicate(@typeName(ComponentType), fields[0..(index + 1)])),
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

fn getEntityHandle(comptime Components: anytype) type {
    _ = Components;
    const typeInfo = comptime blk: {
        const T = @TypeOf(Components);
        const typeInfo = @typeInfo(T).Struct;

        var fields: [typeInfo.fields.len + 1]std.builtin.TypeInfo.StructField = undefined;

        fields[0] = .{
            .name = "ref",
            .field_type = *const EntityRef,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(*const EntityRef),
        };

        // Fill field type info for all components with non-zero size
        inline for (typeInfo.fields) |field, index| {
            const ComponentType = field.default_value orelse unreachable;

            std.debug.assert(@TypeOf(ComponentType) == type);
            if (@sizeOf(ComponentType) > 0) {
                fields[index + 1] = .{
                    .name = componentNameToFieldName(deduplicate(@typeName(ComponentType), fields[0..(index + 1)])),
                    .field_type = *ComponentType,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(*ComponentType),
                };
            } else {
                fields[index + 1] = .{
                    .name = componentNameToFieldName(deduplicate(@typeName(ComponentType), fields[0..(index + 1)])),
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
