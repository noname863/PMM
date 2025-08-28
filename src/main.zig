const std = @import("std");
const SimpleArena = @import("utils/simple_arena.zig").SimpleArena;

const BufferedFileWriter = @TypeOf(std.io.bufferedWriter(std.io.getStdOut().writer())).Writer;

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
                try recipe_dir.openDir(child_dir.name, .{.iterate = true, .no_follow = true}));

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

fn checkPackages(stdout: BufferedFileWriter, recipe_dir: std.fs.Dir) !void
{
    const packages_dir = try recipe_dir.openDir("packages",
        .{.iterate = true, .no_follow = true});
    
    const pmstates = try getPMStates(packages_dir);
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

fn runAttachedProcess(buf_stderr: BufferedFileWriter, argv: []const []const u8, op_name: []const u8) !bool
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
                try buf_stderr.print("{s} step failed, stopping\n", .{op_name});
                return false;
            }
        },
        .Signal => |signal| {
            try buf_stderr.print("{s} returned with signal {}", .{op_name, signal});
            return false;
        },
        .Stopped => |stopped| {
            try buf_stderr.print("{s} stopped with code {}", .{op_name, stopped});
            return false;
        },
        .Unknown => |unknown| {
            try buf_stderr.print("{s} stopped with unknown reason. Returned code {}", .{op_name, unknown});
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

fn applyPackages(buf_stderr: BufferedFileWriter, recipe_dir: std.fs.Dir) !void
{
    const pmstates = try getPMStates(recipe_dir);

    for (pmstates) |pmstate|
    {
        const diff = try packageDiff(pmstate.installed_packages, pmstate.requested_packages);
        // now, we have to
        // 1. pass stdout to user and pass stdin to process
        // 2. detect when user decided to abort installation, in case some packages in recipe are broken

        if (!try runAttachedProcess(buf_stderr,
                try concatArgs(pmstate.package_manager.uninstall_cmd, diff.toRemove), "Uninstall") or
            !try runAttachedProcess(buf_stderr, pmstate.package_manager.remove_excessive_cmd, "Remove excessive") or
            !try runAttachedProcess(buf_stderr,
                try concatArgs(pmstate.package_manager.install_cmd, diff.toAdd), "Install"))
        {
            return;
        }
    }
}

fn lstat(dir: std.fs.Dir, path: []const u8, follow: bool) std.fs.Dir.StatFileError!std.fs.File.Stat
{
    const sub_path_c = try std.posix.toPosixPath(path);
    var stx = std.mem.zeroes(std.os.linux.Statx);

    var mask: u32 = std.os.linux.AT.NO_AUTOMOUNT;
    if (!follow)
    {
        mask |= std.os.linux.AT.SYMLINK_NOFOLLOW;
    }
    const rc = std.os.linux.statx(
        dir.fd,
        &sub_path_c,
        std.os.linux.AT.NO_AUTOMOUNT | std.os.linux.AT.SYMLINK_NOFOLLOW,
        std.os.linux.STATX_TYPE | std.os.linux.STATX_MODE | std.os.linux.STATX_ATIME | std.os.linux.STATX_MTIME | std.os.linux.STATX_CTIME,
        &stx,
    );

    return switch (std.os.linux.E.init(rc)) {
        .SUCCESS => std.fs.File.Stat.fromLinux(stx),
        .ACCES => error.AccessDenied,
        .BADF => unreachable,
        .FAULT => unreachable,
        .INVAL => unreachable,
        .LOOP => error.SymLinkLoop,
        .NAMETOOLONG => unreachable, // Handled by posix.toPosixPath() above.
        .NOENT, .NOTDIR => error.FileNotFound,
        .NOMEM => error.SystemResources,
        else => |err| std.posix.unexpectedErrno(err),
    };
}

const StowContext = struct
{
    stderr: *const BufferedFileWriter,
    overwrite: bool
};

fn SameFileFunc(ContextType: type) type
{
    return *const fn(ContextType, std.fs.Dir, std.fs.Dir, std.fs.Dir.Entry, std.fs.Dir.Stat) anyerror!void; 
}

fn FileNotExistsFunc(ContextType: type) type
{
    return *const fn(ContextType, std.fs.Dir, std.fs.Dir, std.fs.Dir.Entry) anyerror!void; 
}

const DirKind = std.fs.Dir.Entry.Kind;

fn getPathStr(dir: std.fs.Dir, child_name: []const u8, path_buf: []u8) ![]u8
{
    var path_slice = try dir.realpath(child_name, path_buf);

    path_buf[path_slice.len] = '/';
    @memcpy(path_buf[(path_slice.len + 1)..], child_name);
    path_slice.len += 1 + child_name.len;
    return path_slice;
}

fn stowMakeLink(config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    // var path: [std.fs.max_path_bytes]u8 = undefined;
    var path: [std.fs.max_path_bytes]u8 = undefined;
    const path_slice = try config_dir.realpath(file.name, &path);
    try deploy_dir.symLink(path_slice, file.name, .{.is_directory = (file.kind == DirKind.directory)});
}

fn stowSameFunc(context: StowContext, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry, _: std.fs.Dir.Stat) !void
{
    if(context.overwrite)
    {
        try deploy_dir.deleteTree(file.name);
        try stowMakeLink(config_dir, deploy_dir, file);
    }
    else
    {
        var package_path: [std.fs.max_path_bytes]u8 = undefined;
        const package_path_slice = try config_dir.realpath(file.name, &package_path);

        var filesystem_path: [std.fs.max_path_bytes]u8 = undefined;
        const filesystem_path_slice = try deploy_dir.realpath(file.name, &filesystem_path);
        // TODO: consider reverting everything done (would make program much harder)
        try context.stderr.print("Deploing local files would cause overwrites, returning early.\n" ++
            "Some of symlinks may be created. Path which is in both config, and in filesystem:\n" ++
            "Package: {s}\n" ++
            "Filesystem: {s}\n",
            .{package_path_slice, filesystem_path_slice});
    }
}

fn stowNotExists(_: StowContext, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    try stowMakeLink(config_dir, deploy_dir, file);
}

fn iterateSpecificConfig(context: anytype, package_dir: std.fs.Dir, deploy_dir: std.fs.Dir,
    same_name_func: SameFileFunc(@TypeOf(context)),
    not_exists_func: FileNotExistsFunc(@TypeOf(context))) !void
{
    var dir_iter = package_dir.iterateAssumeFirstIteration();

    while (try dir_iter.next()) |dir_entry|
    {
        if (dir_entry.kind != DirKind.file and
            dir_entry.kind != DirKind.directory)
        {
            continue;
        }

        if (lstat(deploy_dir, dir_entry.name, false)) |stat|
        {
            if (dir_entry.kind == stat.kind and
                dir_entry.kind == DirKind.directory)
            {
                try iterateSpecificConfig(
                    context, 
                    try package_dir.openDir(dir_entry.name, .{.iterate = true, .no_follow = true}),
                    try deploy_dir.openDir(dir_entry.name, .{.iterate = false, .no_follow = true}),
                    same_name_func, not_exists_func
                );
            }
            else
            {
                try same_name_func(context, package_dir, deploy_dir, dir_entry, stat);
            }
            // if both exists we should check that file kinds are the same
            // (even if in deploy dir they )
        }
        else |err|
        {
            if (err == error.FileNotFound)
            {
                try not_exists_func(context, package_dir, deploy_dir, dir_entry);
            }
            else
            {
                return err;
            }
        }
    }
}

fn iterateConfig(context: anytype, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir,
    same_name_func: SameFileFunc(@TypeOf(context)),
    not_exists_func: FileNotExistsFunc(@TypeOf(context))) !void
{
    var dir_iter = config_dir.iterateAssumeFirstIteration();

    while (try dir_iter.next()) |package_entry|
    {
        if (package_entry.kind != std.fs.Dir.Entry.Kind.directory)
        {
            continue;
        }

        const package_dir = try config_dir.openDir(package_entry.name, .{.iterate = true, .no_follow = true });

        try iterateSpecificConfig(context, package_dir, deploy_dir, same_name_func, not_exists_func);
    }
}

fn iterateConfigFromHome(context: anytype, packages_dir: std.fs.Dir,
    same_name_func: SameFileFunc(@TypeOf(context)),
    not_exists_func: FileNotExistsFunc(@TypeOf(context))) !void
{
    const config_dir = try packages_dir.openDir("config",
        .{.iterate = true, .no_follow = true});

    // home
    if (std.posix.getenv("HOME")) |home|
    {
        const deploy_dir = try std.fs.openDirAbsolute(home, .{.iterate = false, .no_follow = true});
        // const deploy_dir
        try iterateConfig(context, config_dir, deploy_dir, same_name_func, not_exists_func);
    }
    else
    {
        try context.stderr.print("Home not found! Stopping...\n", .{});
        return;
    }
}

fn applyHome(stderr: BufferedFileWriter, packages_dir: std.fs.Dir, overwrite: bool) !void
{
    try iterateConfigFromHome(StowContext{.stderr = &stderr, .overwrite = overwrite}, packages_dir, stowSameFunc, stowNotExists);
}

const UnstowContext = struct
{
    stderr: *const BufferedFileWriter
};

fn unstowSameFile(context: UnstowContext, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry, stat: std.fs.Dir.Stat) !void
{
    if (file.kind == stat.kind)
    {
        var package_path: [std.fs.max_path_bytes]u8 = undefined;
        const package_path_slice = try config_dir.realpath(file.name, &package_path);

        var filesystem_path: [std.fs.max_path_bytes]u8 = undefined;
        const filesystem_path_slice = try deploy_dir.realpath(file.name, &filesystem_path);
        // TODO: consider reverting everything done (would make program much harder)
        try context.stderr.print("Warning: there was a file instead of a symlink, which corresponded to the file in the config.\n" ++
            "File in the package: {s}\n" ++
            "File in the system: {s}\n",
            .{package_path_slice, filesystem_path_slice});
    }
    else if (stat.kind == DirKind.sym_link)
    {
        try deploy_dir.deleteFile(file.name);
    }
}

fn unstowNotExists(context: UnstowContext,
    config_dir: std.fs.Dir, _: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    var package_path: [std.fs.max_path_bytes]u8 = undefined;
    const package_path_slice = try config_dir.realpath(file.name, &package_path);
    try context.stderr.print("Warning: file which should correspond to the {s} wasn't found\n", .{package_path_slice});
}

fn cleanupHome(stderr: BufferedFileWriter, packages_dir: std.fs.Dir) !void
{
    try iterateConfigFromHome(UnstowContext{.stderr = &stderr}, packages_dir, unstowSameFile, unstowNotExists);
}

const StdoutContext = struct
{
    stdout: *const BufferedFileWriter,
    stderr: *const BufferedFileWriter,
};

fn append(a: []u8, b: []const u8) []u8
{
    var temp = a;
    temp.len = a.len + b.len;

    @memcpy(temp[a.len..temp.len], b);
    return temp;
}

fn previewApplySameFile(context: StdoutContext, _: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry, _: std.fs.Dir.Stat) !void
{
    var path: [std.fs.max_path_bytes]u8 = undefined;
    const path_slice = try deploy_dir.realpath(file.name, &path);
    try context.stdout.print("Overwrite: {s}\n", .{path_slice});
}

fn previewApplyNotFound(context: StdoutContext, _: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    var path: [std.fs.max_path_bytes]u8 = undefined;
    var path_slice = try deploy_dir.realpath(".", &path);
    path_slice = append(path_slice, "/");
    path_slice = append(path_slice, file.name);
    
    try context.stdout.print("Deploy: {s}\n", .{path_slice});
}

// TODO: print all warnings in stderr instead of stdout
fn previewApplyHome(stdout: BufferedFileWriter, stderr: BufferedFileWriter, packages_dir: std.fs.Dir) !void
{
    try iterateConfigFromHome(StdoutContext{.stdout = &stdout, .stderr = &stderr},
        packages_dir, previewApplySameFile, previewApplyNotFound);
}

fn previewCleanupSameFile(context: StdoutContext, _: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry, stat: std.fs.Dir.Stat) !void
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

fn previewCleanupNotFound(context: StdoutContext, _: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    var path: [std.fs.max_path_bytes]u8 = undefined;
    var path_slice = try deploy_dir.realpath(".", &path);
    path_slice = append(path_slice, "/");
    path_slice = append(path_slice, file.name);
    
    try context.stdout.print("Missing: {s}\n", .{path_slice});
}

fn previewCleanupHome(stdout: BufferedFileWriter, stderr: BufferedFileWriter, packages_dir: std.fs.Dir) !void
{
    try iterateConfigFromHome(StdoutContext{.stdout = &stdout, .stderr = &stderr},
        packages_dir, previewCleanupSameFile, previewCleanupNotFound);
}

fn processAccessDenied(stdout: BufferedFileWriter, err: anyerror) !void
{
    if (err == error.AccessDenied)
    {
        try stdout.print("Access Denied when trying to do operation." ++
            "Consider running tool with sudo.\n", .{});
    }
    else
    {
        return err;
    }
}

pub fn main() !void {
    // TODO: add a lot of error handling. For now if something goes wrong
    // I will recieve debug messages, and stacktrace, but need to consider
    // something nicer for stuff which will face user
    defer arena.deinit();

    var stdout_buf_handle = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout: BufferedFileWriter = stdout_buf_handle.writer();

    var stderr_buf_handle = std.io.bufferedWriter(std.io.getStdErr().writer());
    const stderr: BufferedFileWriter = stderr_buf_handle.writer();

    defer (stdout.context.flush() catch {});

    if (std.os.argv.len < 3)
    {
        // TODO, print help in all places where relevant
        try stdout.print("Too little command line arguments\n", .{});
        return;
    }
    const folderArg = std.mem.span(std.os.argv[1]);

    const recipe_dir: std.fs.Dir = std.fs.cwd().openDir(folderArg,
        std.fs.Dir.OpenOptions{.iterate = false, .no_follow = true}) catch
    {
        try stdout.print("Command argument wasn't a directory\n", .{});
        return;
    };

    if (std.mem.orderZ(u8, std.os.argv[2], "--check-packages") == .eq)
    {
        checkPackages(stdout, recipe_dir) catch |err| {
            try processAccessDenied(stdout, err);
        };
        return;
    }

    if (std.mem.orderZ(u8, std.os.argv[2], "--apply-packages") == .eq)
    {
        applyPackages(stderr, recipe_dir) catch |err| {
            try processAccessDenied(stdout, err);
        };
        return;
    }

    if (std.mem.orderZ(u8, std.os.argv[2], "--apply-home") == .eq)
    {
        applyHome(stderr, recipe_dir, false) catch |err| {
            try processAccessDenied(stdout, err);
        };
        return;
    }

    if (std.mem.orderZ(u8, std.os.argv[2], "--cleanup-home") == .eq)
    {
        cleanupHome(stderr, recipe_dir) catch |err| {
            try processAccessDenied(stdout, err);
        };
        return;
    }

    if (std.mem.orderZ(u8, std.os.argv[2], "--preview-apply-home") == .eq)
    {
        previewApplyHome(stdout, stderr, recipe_dir) catch |err| {
            try processAccessDenied(stdout, err);
        };
        return;
    }

    if (std.mem.orderZ(u8, std.os.argv[2], "--preview-cleanup-home") == .eq)
    {
        previewCleanupHome(stdout, stderr, recipe_dir) catch |err| {
            try processAccessDenied(stdout, err);
        };

        return;
    }

    try stdout.print("Unknown argument", .{});
}

