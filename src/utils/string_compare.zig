const std = @import("std");

pub fn stringCompare(_: void, lhs: []const u8, rhs: []const u8) bool
{
    return std.mem.lessThan(u8, lhs, rhs);
}

