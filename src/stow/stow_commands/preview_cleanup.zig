const std = @import("std");
const append = @import("../../utils/append.zig").append;


const DirKind = std.fs.Dir.Entry.Kind;

pub const Context = struct
{
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
};

pub fn same(context: Context, _: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry, stat: std.fs.Dir.Stat) !void
{
    var path: [std.fs.max_path_bytes]u8 = undefined;
    const path_slice = try deploy_dir.realpath(file.name, &path);
    if (stat.kind == DirKind.sym_link)
    {
        try context.stdout.print("Removed: {s}\n", .{path_slice});
    }
    else
    {
        try context.stdout.print("Excessive: {s}\n", .{path_slice});
    }
}

pub fn notExists(context: Context, _: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    var path: [std.fs.max_path_bytes]u8 = undefined;
    var path_slice = try deploy_dir.realpath(".", &path);
    path_slice = append(u8, path_slice, "/");
    path_slice = append(u8, path_slice, file.name);
    
    try context.stdout.print("Missing: {s}\n", .{path_slice});
}

pub fn createContext(stdout: *std.Io.Writer, stderr: *std.Io.Writer) Context
{
    return Context{.stdout = stdout, .stderr = stderr};
}

