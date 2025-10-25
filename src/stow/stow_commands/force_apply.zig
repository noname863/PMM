const apply = @import("apply.zig");
const std = @import("std");

pub const Context = apply.Context;

pub const same = apply.same;
pub const notExists = apply.notExists;

pub fn createContext(_: *std.Io.Writer, stderr: *std.Io.Writer) Context
{
    return .{
        .stderr = stderr,
        .overwrite = true,
    };
}

