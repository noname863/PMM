// By convention, main.zig is where your main function lives in the case that
// you are building an executable. If you are making a library, the convention
// is to delete this file and start with root.zig instead.
const std = @import("std");

pub fn main() !void {
    var stdout_buf_handle = std.io.bufferedWriter(std.io.getStdOut().writer());
    var stdout = stdout_buf_handle.writer();

    defer stdout.context.flush() catch {};

    if (std.os.argv.len < 2)
    {
        try stdout.print("Too little command line arguments\n", .{});
        return;
    }
    const folderArg = std.mem.span(std.os.argv[1]);

    var dir: std.fs.Dir = std.fs.cwd().openDir(folderArg,
        std.fs.Dir.OpenOptions{.access_sub_paths = true, .iterate = true, .no_follow = true}) catch
    {
        try stdout.print("Command argument wasn't a directory", .{});
        return;
    };

    var dir_iter = dir.iterateAssumeFirstIteration();

    while (try dir_iter.next()) |child_dir|
    {
        try stdout.print("{s}\n", .{child_dir.name});
    }

    try stdout.context.flush();
}

