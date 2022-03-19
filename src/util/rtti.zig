const std = @import("std");

pub fn typeId(comptime T: type) TypeId {
    return TypeId{ .typeInfo = typeInfo(T) };
}

fn structFields(comptime T: type) []const TypeInfoKind.StructField {
    const ti = @typeInfo(T).Struct;
    var fields = &struct {
        var _fields: [ti.fields.len]TypeInfoKind.StructField = undefined;
    }._fields;
    inline for (ti.fields) |field, i| {
        fields[i] = .{
            .name = field.name,
            .field_type = typeInfo(field.field_type),
            .offset = if (@sizeOf(field.field_type) > 0) @offsetOf(T, field.name) else 0,
            // .default_value= anytype,
            .is_comptime = field.is_comptime,
            .alignment = field.alignment,
        };
    }
    return fields;
}

pub fn typeInfo(comptime T: type) *const TypeInfo {
    if (T == *anyopaque)
        return typeInfo(void);

    if (comptime std.mem.indexOf(u8, @typeName(T), ".cimport") != null) {
        return typeInfo(void);
    }

    var result = &struct {
        var x: TypeInfo = .{
            .hash = 0,
            .name = @typeName(T),
            .size = @sizeOf(T),
            .alignment = if (T == void) 0 else @alignOf(T),
            .kind = .Void,
        };
    }.x;

    if (result.hash == 0) {
        result.hash = std.hash.Wyhash.hash(69, @typeName(T));

        switch (@typeInfo(T)) {
            .Type => {
                result.kind = .Type;
            },
            .Void => {
                result.kind = .Void;
            },
            .Bool => {
                result.kind = .Bool;
            },
            .NoReturn => {
                result.kind = .NoReturn;
            },
            .Int => |info| {
                result.kind = TypeInfoKind{ .Int = .{ .signedness = info.signedness, .bits = info.bits } };
            },
            .Float => |info| {
                result.kind = TypeInfoKind{ .Float = .{ .bits = info.bits } };
            },
            .Pointer => |info| {
                result.kind = TypeInfoKind{ .Pointer = .{
                    .size = info.size,
                    .is_const = info.is_const,
                    .is_volatile = info.is_volatile,
                    .alignment = info.alignment,
                    .address_space = info.address_space,
                    .child = typeInfo(info.child),
                    .is_allowzero = info.is_allowzero,
                } };
            },
            .Array => |info| {
                result.kind = TypeInfoKind{ .Array = .{
                    .len = info.len,
                    .child = typeInfo(info.child),
                } };
                _ = info;
            },
            .Struct => |info| {
                result.kind = TypeInfoKind{ .Struct = .{
                    .layout = info.layout,
                    .fields = structFields(T),
                    .decls = &.{},
                    .is_tuple = info.is_tuple,
                } };
            },
            .ComptimeFloat => {
                result.kind = .ComptimeFloat;
            },
            .ComptimeInt => {
                result.kind = .ComptimeInt;
            },
            .Undefined => {
                result.kind = .Undefined;
            },
            .Null => {
                result.kind = .Null;
            },
            .Optional => |info| {
                result.kind = TypeInfoKind{ .Optional = .{ .child = typeInfo(info.child) } };
            },
            .ErrorUnion => |info| {
                result.kind = TypeInfoKind{ .ErrorUnion = .{
                    .error_set = typeInfo(info.error_set),
                    .payload = typeInfo(info.payload),
                } };
            },
            .ErrorSet => |info| {
                result.kind = TypeInfoKind{ .ErrorSet = null };
                _ = info;
            },
            .Enum => |info| {
                result.kind = TypeInfoKind{ .Enum = .{
                    .layout = info.layout,
                    .tag_type = typeInfo(info.tag_type),
                    .fields = &.{},
                    .decls = &.{},
                    .is_exhaustive = info.is_exhaustive,
                } };
            },
            .Union => |info| {
                result.kind = TypeInfoKind{ .Union = .{
                    .layout = info.layout,
                    .tag_type = if (info.tag_type) |t| typeInfo(t) else null,
                    .fields = &.{},
                    .decls = &.{},
                } };
            },
            .Fn => |info| {
                result.kind = TypeInfoKind{ .Fn = .{
                    .calling_convention = info.calling_convention,
                    .alignment = info.alignment,
                    .is_generic = info.is_generic,
                    .is_var_args = info.is_var_args,
                    .return_type = if (info.return_type) |t| typeInfo(t) else null,
                    .args = &.{},
                } };
            },
            .BoundFn => |info| {
                result.kind = TypeInfoKind{ .Fn = .{
                    .calling_convention = info.calling_convention,
                    .alignment = info.alignment,
                    .is_generic = info.is_generic,
                    .is_var_args = info.is_var_args,
                    .return_type = if (info.return_type) |t| typeInfo(t) else null,
                    .args = &.{},
                } };
            },
            .Opaque => |info| {
                result.kind = TypeInfoKind{ .Opaque = .{
                    .decls = &.{},
                } };
                _ = info;
            },
            .Frame => |info| {
                result.kind = TypeInfoKind{ .Frame = .{} };
                _ = info;
            },
            .AnyFrame => |info| {
                result.kind = TypeInfoKind{ .AnyFrame = .{
                    .child = if (info.child) |t| typeInfo(t) else null,
                } };
            },
            .Vector => |info| {
                result.kind = TypeInfoKind{ .Vector = .{
                    .len = info.len,
                    .child = typeInfo(info.child),
                } };
            },
            .EnumLiteral => {
                result.kind = .EnumLiteral;
            },
        }
    }

    return result;
}

pub const TypeId = struct {
    typeInfo: *const TypeInfo,

    pub fn format(self: *const TypeId, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "{}", .{self.typeInfo.*});
    }
};

pub const TypeInfoKind = union(enum) {
    Type: void,
    Void: void,
    Bool: void,
    NoReturn: void,
    Int: Int,
    Float: Float,
    Pointer: Pointer,
    Array: Array,
    Struct: Struct,
    ComptimeFloat: void,
    ComptimeInt: void,
    Undefined: void,
    Null: void,
    Optional: Optional,
    ErrorUnion: ErrorUnion,
    ErrorSet: ErrorSet,
    Enum: Enum,
    Union: Union,
    Fn: Fn,
    BoundFn: Fn,
    Opaque: Opaque,
    Frame: Frame,
    AnyFrame: AnyFrame,
    Vector: Vector,
    EnumLiteral: void,

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Int = struct {
        signedness: std.builtin.Signedness,
        bits: u16,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Float = struct {
        bits: u16,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Pointer = struct {
        size: std.builtin.TypeInfo.Pointer.Size,
        is_const: bool,
        is_volatile: bool,
        alignment: u16,
        address_space: std.builtin.AddressSpace,
        child: *const TypeInfo,
        is_allowzero: bool,

        // /// This field is an optional type.
        // /// The type of the sentinel is the element type of the pointer, which is
        // /// the value of the `child` field in this struct. However there is no way
        // /// to refer to that type here, so we use `anytype`.
        // sentinel: anytype,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Array = struct {
        len: u64,
        child: *const TypeInfo,

        // /// This field is an optional type.
        // /// The type of the sentinel is the element type of the array, which is
        // /// the value of the `child` field in this struct. However there is no way
        // /// to refer to that type here, so we use `anytype`.
        // sentinel: anytype,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const StructField = struct {
        name: []const u8,
        field_type: *const TypeInfo,
        offset: u64,
        // default_value: anytype,
        is_comptime: bool,
        alignment: u16,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Struct = struct {
        layout: std.builtin.TypeInfo.ContainerLayout,
        fields: []const StructField,
        decls: []const Declaration,
        is_tuple: bool,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Optional = struct {
        child: *const TypeInfo,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const ErrorUnion = struct {
        error_set: *const TypeInfo,
        payload: *const TypeInfo,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Error = struct {
        name: []const u8,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const ErrorSet = ?[]const Error;

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const EnumField = struct {
        name: []const u8,
        value: u64,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Enum = struct {
        layout: std.builtin.TypeInfo.ContainerLayout,
        tag_type: *const TypeInfo,
        fields: []const EnumField,
        decls: []const Declaration,
        is_exhaustive: bool,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const UnionField = struct {
        name: []const u8,
        field_type: *const TypeInfo,
        alignment: u16,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Union = struct {
        layout: std.builtin.TypeInfo.ContainerLayout,
        tag_type: ?*const TypeInfo,
        fields: []const UnionField,
        decls: []const Declaration,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const FnArg = struct {
        is_generic: bool,
        is_noalias: bool,
        arg_type: ?*const TypeInfo,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Fn = struct {
        calling_convention: std.builtin.CallingConvention,
        alignment: u16,
        is_generic: bool,
        is_var_args: bool,
        return_type: ?*const TypeInfo,
        args: []const FnArg,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Opaque = struct {
        decls: []const Declaration,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Frame = struct {
        // function: fn () void,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const AnyFrame = struct {
        child: ?*const TypeInfo,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Vector = struct {
        len: u64,
        child: *const TypeInfo,
    };

    /// This data structure is used by the Zig language code generation and
    /// therefore must be kept in sync with the compiler implementation.
    pub const Declaration = struct {
        name: []const u8,
        is_pub: bool,
        data: Data,

        /// This data structure is used by the Zig language code generation and
        /// therefore must be kept in sync with the compiler implementation.
        pub const Data = union(enum) {
            Type: *const TypeInfo,
            Var: *const TypeInfo,
            Fn: FnDecl,

            /// This data structure is used by the Zig language code generation and
            /// therefore must be kept in sync with the compiler implementation.
            pub const FnDecl = struct {
                fn_type: *const TypeInfo,
                is_noinline: bool,
                is_var_args: bool,
                is_extern: bool,
                is_export: bool,
                lib_name: ?[]const u8,
                return_type: *const TypeInfo,
                arg_names: []const []const u8,
            };
        };
    };
};

pub const TypeInfo = struct {
    const Self = @This();

    hash: u64,
    name: []const u8,
    size: u32,
    alignment: u32,

    kind: TypeInfoKind,

    pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "{s}", .{self.name});
    }

    pub fn typeId(self: *const Self) TypeId {
        return TypeId{ .typeInfo = self };
    }
};
