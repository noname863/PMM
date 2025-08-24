const std = @import("std");
const SimpleArena = @import("utils/simple_arena.zig").SimpleArena;

var arena = SimpleArena(1048576).init();

fn checkPackages(stdout: anytype, packageManager: *const PackageManager) !void {
    const allocator = arena.allocator();

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = packageManager.userInstalledPackagesCmd,
    });

    try stdout.print("{s}", .{result.stdout});
}

const PackageManager = struct
{
    name: []const u8,
    userInstalledPackagesCmd: []const []const u8,
    // allInstalledPackagesCmd: [][]const u8,
};

const package_managers: [1]PackageManager = .{
    .{
        .name = "dnf",
        .userInstalledPackagesCmd = &.{"dnf", "repoquery", "--userinstalled", "--queryformat=%{name}\n"}
    },
};

fn getPackageManager(packageDir: std.fs.Dir.Entry) ?*const PackageManager
{
    for (package_managers) |manager|
    {
        if (std.mem.eql(u8, packageDir.name, manager.name))
        {
            return &manager;
        }
    }
    return null;
}

pub fn main() !void {
    defer arena.deinit();

    var stdout_buf_handle = std.io.bufferedWriter(std.io.getStdOut().writer());
    var stdout = stdout_buf_handle.writer();

    defer stdout.context.flush() catch {};

    if (std.os.argv.len < 2)
    {
        try stdout.print("Too little command line arguments\n", .{});
        return;
    }
    const folderArg = std.mem.span(std.os.argv[1]);

    var recipyDir: std.fs.Dir = std.fs.cwd().openDir(folderArg,
        std.fs.Dir.OpenOptions{.access_sub_paths = true, .iterate = true, .no_follow = true}) catch
    {
        try stdout.print("Command argument wasn't a directory", .{});
        return;
    };

    var dir_iter = recipyDir.iterateAssumeFirstIteration();

    while (try dir_iter.next()) |child_dir|
    {
        if (child_dir.kind != std.fs.File.Kind.directory)
        {
            continue;
        }

        if (getPackageManager(child_dir)) |manager|
        {
            try checkPackages(stdout, manager);
        }
        try stdout.print("{s}\n", .{child_dir.name});
    }

    try stdout.context.flush();
}

