const std = @import("std");

// pub const TypeId = struct {
//     typeInfo: *Self,

//     pub const Context = struct {
//         pub fn hash(context: @This(), self: TypeId) u64 {
//             _ = context;
//             return @ptrToInt(self.typeInfo);
//         }
//         pub fn eql(context: @This(), a: TypeId, b: TypeId) bool {
//             _ = context;
//             return a.typeInfo == b.typeInfo;
//         }
//     };
// };

hash: u64,
name: []const u8,
id: u64,
size: u32,
alignment: u32,

const Self = @This();
pub const TypeId = Self;

pub fn typeInfo(comptime T: type) u64 {
    _ = T;
    return @ptrToInt(&struct {
        // var x: Self = ;
        var x: u8 = 0;
    }.x);
}

pub fn typeId(comptime T: type) TypeId {
    // return TypeId{ .id = typeInfo(T) };
    return aetypeid(T);
}

pub fn aetypeid(comptime T: type) Self {
    const hash = comptime std.hash.Wyhash.hash(69, @typeName(T));
    return Self{
        .hash = hash,
        .name = @typeName(T),
        .id = typeInfo(T),
        .size = @sizeOf(T),
        .alignment = @alignOf(T),
    };
}

pub const Context = struct {
    pub fn hash(context: @This(), self: Self) u64 {
        _ = context;
        return self.hash;
    }
    pub fn eql(context: @This(), a: Self, b: Self) bool {
        _ = context;

        if (a.hash != b.hash) {
            return false;
        }

        return a.id == b.id;
    }
};

pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "{s}", .{self.name});
}
