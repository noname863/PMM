const std = @import("std");
const BufferedFileWriter = @import("../utils/buffered_writer.zig").BufferedFileWriter;
const arena = @import("../utils/simple_arena.zig");

pub fn checkProcessFailure(stderr: *const BufferedFileWriter,
    op_name: []const u8, proc_result: std.process.Child.Term) !bool
{
    switch (proc_result)
    {
        .Exited => |code| {
            if (code != 0)
            {
                try stderr.print("{s} step failed, stopping\n", .{op_name});
                return false;
            }
            else
            {
                return true;
            }
        },
        .Signal => |signal| {
            try stderr.print("{s} returned with signal {}", .{op_name, signal});
            return false;
        },
        .Stopped => |stopped| {
            try stderr.print("{s} stopped with code {}", .{op_name, stopped});
            return false;
        },
        .Unknown => |unknown| {
            try stderr.print("{s} stopped with unknown reason. Returned code {}", .{op_name, unknown});
            return false;
        }
    }
}

pub fn runAttachedProcess(stderr: *const BufferedFileWriter, argv: []const []const u8, op_name: []const u8) !bool
{
    var child_process = std.process.Child.init(argv, arena.instance.allocator());
    child_process.stdin_behavior = std.process.Child.StdIo.Inherit;
    child_process.stdout_behavior = std.process.Child.StdIo.Inherit;
    child_process.stderr_behavior = std.process.Child.StdIo.Inherit;

    const proc_result = try child_process.spawnAndWait();

    return try checkProcessFailure(stderr, op_name, proc_result);
}

