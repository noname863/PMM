const std = @import("std");
const arena = @import("../utils/simple_arena.zig");

pub fn parsePackages(packages: *std.ArrayList([]const u8), string_with_packages: []const u8) !void
{
    var start_index: usize = 0;

    while (std.mem.indexOfScalarPos(u8, string_with_packages, start_index, '\n')) |end_index|
    {
        defer start_index = end_index + 1;
        if (string_with_packages[start_index] == '#')
        {
            continue;
        }

        if (std.mem.indexOfNone(u8, string_with_packages[start_index..end_index], &std.ascii.whitespace)) |index_of_first_letter|
        {
            try packages.append(arena.allocator, string_with_packages[(start_index+index_of_first_letter)..end_index]);
        }
    }
}

