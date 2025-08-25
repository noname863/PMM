const std = @import("std");
const SimpleArena = @import("utils/simple_arena.zig").SimpleArena;

var arena = SimpleArena(1048576).init();

const PackageDiff = struct
{
    toRemove: []const []const u8,
    toAdd: []const []const u8
};

fn stringCompare(_: void, lhs: []const u8, rhs: []const u8) bool
{
    return std.mem.lessThan(u8, lhs, rhs);
}

fn packageDiff(installed: []const []const u8, in_recipe: []const []const u8) !PackageDiff
{
    // TODO: two array lists work poorly with one arena.
    // Ideally, you would like to have separate arenas for them
    var to_add = std.ArrayList([]const u8).init(arena.allocator());
    var to_remove = std.ArrayList([]const u8).init(arena.allocator());

    var installed_index: usize = 0;
    var recipe_index: usize = 0;

    while (true)
    {
        if (installed_index == installed.len)
        {
            while (recipe_index < in_recipe.len)
            {
                try to_add.append(in_recipe[recipe_index]);
                recipe_index += 1;
            }
            break;
        }
        if (recipe_index == in_recipe.len)
        {
            while (installed_index < installed.len)
            {
                try to_remove.append(installed[installed_index]);
                installed_index += 1;
            }
        }

        switch (std.mem.order(u8, installed[installed_index], in_recipe[recipe_index]))
        {
            .lt => {
                try to_remove.append(installed[installed_index]);
                installed_index += 1;
            },
            .eq => {
                installed_index += 1;
                recipe_index += 1;
            },
            .gt => {
                try to_add.append(in_recipe[recipe_index]);
                recipe_index += 1;
            }
        }
        // installed[installed_index]
    }

    return PackageDiff{.toAdd = to_add.items, .toRemove = to_remove.items };
}

fn parcePackages(packages: *std.ArrayList([]const u8), string_with_packages: []const u8) !void
{
    var start_index: usize = 0;

    while (std.mem.indexOfScalarPos(u8, string_with_packages, start_index, '\n')) |end_index|
    {
        if (std.mem.indexOfNone(u8, string_with_packages[start_index..end_index], &std.ascii.whitespace) != null and
            string_with_packages[start_index] != '#')
        {
            try packages.append(string_with_packages[start_index..end_index]);
        }
        start_index = end_index + 1;
    }
}

fn gatherPackages(pmfolder: std.fs.Dir) ![][]const u8
{
    const allocator = arena.allocator();
    var dir_iter = pmfolder.iterateAssumeFirstIteration();

    var packages = std.ArrayList([]const u8).init(allocator);

    while (try dir_iter.next()) |file_entry|
    {
        if (file_entry.kind != std.fs.File.Kind.file or
            !std.mem.endsWith(u8, file_entry.name, "packages"))
        {
            continue;
        }

        var file = try pmfolder.openFile(file_entry.name, std.fs.File.OpenFlags{.lock = .shared});
        const file_content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

        try parcePackages(&packages, file_content);
    }

    std.mem.sortUnstable([]const u8, packages.items, {}, stringCompare);

    return packages.items;
}

fn getInstalledPackages(packageManager: *const PackageManager) ![][]const u8{
    const allocator = arena.allocator();

    var packages = std.ArrayList([]const u8).init(allocator);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = packageManager.user_installed_cmd,
    });

    try parcePackages(&packages, result.stdout);
    std.mem.sortUnstable([]const u8, packages.items, {}, stringCompare);

    return packages.items;
}

const PackageManager = struct
{
    name: []const u8,
    user_installed_cmd: []const []const u8,
    remove_excessive_cmd: []const []const u8,
    uninstall_cmd: []const []const u8,
    install_cmd: []const []const u8,

    // cleanup
    // install command
    // remove command
    // allInstalledPackagesCmd: [][]const u8,
};

const PMState = struct
{
    package_manager: *const PackageManager,

    installed_packages: []const []const u8,
    requested_packages: []const []const u8,
};

const package_managers: [1]PackageManager = .{
    .{
        .name = "dnf",
        .user_installed_cmd = &.{"dnf", "repoquery", "--userinstalled", "--queryformat=%{name}\n"},
        .remove_excessive_cmd = &.{"dnf", "autoremove"},
        .uninstall_cmd = &.{"dnf", "remove"},
        .install_cmd = &.{"dnf", "install"}
    },
};

fn getPackageManager(packageDir: std.fs.Dir.Entry) ?u63
{
    var index: u63 = 0;
    while (index < package_managers.len)
    {
        if (std.mem.eql(u8, packageDir.name, package_managers[index].name))
        {
            return index;
        }
        index += 0;
    }
    return null;
}

fn getPMStates(recipe_dir: std.fs.Dir) ![]PMState
{
    var pmstates = std.ArrayList(PMState).init(arena.allocator());
    
    var dir_iter = recipe_dir.iterateAssumeFirstIteration();

    while (try dir_iter.next()) |child_dir|
    {
        if (child_dir.kind != std.fs.File.Kind.directory)
        {
            continue;
        }

        if (getPackageManager(child_dir)) |manager_index|
        {
            const manager = &package_managers[manager_index];
            const requested_packages = try gatherPackages(
                try recipe_dir.openDir(child_dir.name, .{.access_sub_paths = true, .iterate = true, .no_follow = true}));

            const installed = try getInstalledPackages(manager);
            
            try pmstates.append(.{
                .package_manager = manager,
                .installed_packages = installed,
                .requested_packages = requested_packages
            });
        }
    }

    return pmstates.items;
}

fn checkPackages(stdout: anytype, recipe_dir: std.fs.Dir) !void
{
    const pmstates = try getPMStates(recipe_dir);
    for (pmstates) |pmstate|
    {
        try stdout.print("{s} package manager:\n", .{pmstate.package_manager.name});
        const diff = try packageDiff(pmstate.installed_packages, pmstate.requested_packages);

        try stdout.print("Packages missing:\n\n", .{});
        for (diff.toAdd) |toAdd|
        {
            try stdout.print("{s}\n", .{toAdd});
        }

        try stdout.print("\nExcessive packages:\n\n", .{});
        for (diff.toRemove) |toRemove|
        {
            try stdout.print("{s}\n", .{toRemove});
        }
    }
}

fn runAttachedProcess(buf_stdout: anytype, argv: []const []const u8, op_name: []const u8) !bool
{
    var child_process = std.process.Child.init(argv, arena.allocator());
    child_process.stdin_behavior = std.process.Child.StdIo.Inherit;
    child_process.stdout_behavior = std.process.Child.StdIo.Inherit;
    child_process.stderr_behavior = std.process.Child.StdIo.Inherit;

    const proc_result = try child_process.spawnAndWait();

    switch (proc_result)
    {
        .Exited => |code| {
            if (code != 0)
            {
                try buf_stdout.print("{s} step failed, stopping\n", .{op_name});
                return false;
            }
        },
        .Signal => |signal| {
            try buf_stdout.print("{s} returned with signal {}", .{op_name, signal});
            return false;
        },
        .Stopped => |stopped| {
            try buf_stdout.print("{s} stopped with code {}", .{op_name, stopped});
            return false;
        },
        .Unknown => |unknown| {
            try buf_stdout.print("{s} stopped with unknown reason. Returned code {}", .{op_name, unknown});
            return false;
        }
    }

    return true;
}

fn concatArgs(left_args: []const []const u8, right_args: []const []const u8) ![]const []const u8
{
    const allocator = arena.allocator();
    const argv: [][]const u8 = try allocator.alloc([]const u8, left_args.len + right_args.len);
    
    var i: usize = 0;
    while (i < left_args.len)
    {
        argv[i] = left_args[i];
        i += 1;
    }

    while (i - left_args.len < right_args.len)
    {
        argv[i] = right_args[i - left_args.len];
        i += 1;
    }

    return argv;
}

fn applyPackages(buf_stdout: anytype, recipe_dir: std.fs.Dir) !void
{
    const pmstates = try getPMStates(recipe_dir);

    for (pmstates) |pmstate|
    {
        const diff = try packageDiff(pmstate.installed_packages, pmstate.requested_packages);
        // now, we have to
        // 1. pass stdout to user and pass stdin to process
        // 2. detect when user decided to abort installation, in case some packages in recipe are broken

        if (!try runAttachedProcess(buf_stdout,
                try concatArgs(pmstate.package_manager.uninstall_cmd, diff.toRemove), "Uninstall") or
            !try runAttachedProcess(buf_stdout, pmstate.package_manager.remove_excessive_cmd, "Remove excessive") or
            !try runAttachedProcess(buf_stdout,
                try concatArgs(pmstate.package_manager.install_cmd, diff.toAdd), "Install"))
        {
            return;
        }
    }
}

pub fn main() !void {
    defer arena.deinit();

    var stdout_buf_handle = std.io.bufferedWriter(std.io.getStdOut().writer());
    var stdout = stdout_buf_handle.writer();
    defer (stdout.context.flush() catch {});

    if (std.os.argv.len < 3)
    {
        try stdout.print("Too little command line arguments\n", .{});
        return;
    }
    const folderArg = std.mem.span(std.os.argv[1]);

    const recipe_dir: std.fs.Dir = std.fs.cwd().openDir(folderArg,
        std.fs.Dir.OpenOptions{.access_sub_paths = true, .iterate = true, .no_follow = true}) catch
    {
        try stdout.print("Command argument wasn't a directory", .{});
        return;
    };

    if (std.mem.orderZ(u8, std.os.argv[2], "--check-packages") == .eq)
    {
        try checkPackages(stdout, recipe_dir);
    }

    if (std.mem.orderZ(u8, std.os.argv[2], "--apply-packages") == .eq)
    {
        try applyPackages(stdout, recipe_dir);
    }
}

