const std = @import("std");

const Impl = std.bit_set.StaticBitSet(64);

bitSet: Impl,

const Self = @This();

pub fn initEmpty() @This() {
    return @This(){ .bitSet = Impl.initEmpty() };
}
pub fn isSet(self: *Self, index: usize) bool {
    return self.bitSet.isSet(index);
}

pub fn set(self: *Self, index: usize) void {
    self.bitSet.set(index);
}

pub fn unset(self: *Self, index: usize) void {
    self.bitSet.unset(index);
}

pub fn setUnion(self: *Self, other: Self) void {
    self.bitSet.setUnion(other.bitSet);
}

pub fn setIntersection(self: *Self, other: Self) void {
    self.bitSet.setIntersection(other.bitSet);
}

pub fn isSubSetOf(self: *const Self, other: Self) bool {
    var sum = self.*;
    sum.setUnion(other);
    return std.meta.eql(sum, other);
}

pub fn isSuperSetOf(self: *const Self, other: Self) bool {
    var sum = self.*;
    sum.setUnion(other);
    return std.meta.eql(sum, self.*);
}

pub fn subtract(self: *const Self, other: Self) Self {
    var diff = self.*;
    var otherInverse = other;
    otherInverse.bitSet.toggleAll();
    diff.setIntersection(otherInverse);
    return diff;
}

pub fn iterator(self: *const Self) @TypeOf(Impl.initEmpty().iterator(.{})) {
    return self.bitSet.iterator(.{});
}
