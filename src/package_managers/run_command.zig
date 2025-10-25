const std = @import("std");
const arena = @import("../utils/simple_arena.zig");

const stringCompare = @import("../utils/string_compare.zig").stringCompare;

const pm = @import("package_managers.zig");
const parsePackages = @import("parse_packages.zig").parsePackages;

const PackageDiff = struct
{
    toRemove: []const []const u8,
    toAdd: []const []const u8
};

fn packageDiff(installed: []const []const u8, in_recipe: []const []const u8) !PackageDiff
{
    // TODO: two array lists work poorly with one arena.instance.
    // Ideally, you would like to have separate arenas for them
    var to_add = std.ArrayList([]const u8){};
    var to_remove = std.ArrayList([]const u8){};

    var installed_index: usize = 0;
    var recipe_index: usize = 0;

    while (true)
    {
        if (installed_index == installed.len)
        {
            while (recipe_index < in_recipe.len)
            {
                try to_add.append(arena.allocator, in_recipe[recipe_index]);
                recipe_index += 1;
            }
            break;
        }
        if (recipe_index == in_recipe.len)
        {
            while (installed_index < installed.len)
            {
                try to_remove.append(arena.allocator, installed[installed_index]);
                installed_index += 1;
            }
            break;
        }

        switch (std.mem.order(u8, installed[installed_index], in_recipe[recipe_index]))
        {
            .lt => {
                try to_remove.append(arena.allocator, installed[installed_index]);
                installed_index += 1;
            },
            .eq => {
                installed_index += 1;
                recipe_index += 1;
            },
            .gt => {
                try to_add.append(arena.allocator, in_recipe[recipe_index]);
                recipe_index += 1;
            }
        }
        // installed[installed_index]
    }

    return PackageDiff{.toAdd = to_add.items, .toRemove = to_remove.items };
}

fn gatherPackages(pmfolder: std.fs.Dir) ![][]const u8
{
    const allocator = arena.allocator;
    var dir_iter = pmfolder.iterateAssumeFirstIteration();

    var packages = std.ArrayList([]const u8){};

    while (try dir_iter.next()) |file_entry|
    {
        if (file_entry.kind != std.fs.File.Kind.file or
            !std.mem.endsWith(u8, file_entry.name, "packages"))
        {
            continue;
        }

        var file = try pmfolder.openFile(file_entry.name, std.fs.File.OpenFlags{.lock = .shared});
        const file_content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

        try parsePackages(&packages, file_content);
    }

    std.mem.sortUnstable([]const u8, packages.items, {}, stringCompare);

    return packages.items;
}

fn getPackageManager(packageDir: std.fs.Dir.Entry) ?*const pm.PackageManager
{
    for (&pm.package_managers) |*package_manager|
    {
        if (std.mem.eql(u8, packageDir.name, package_manager.name))
        {
            return package_manager;
        }
    }
    return null;
}

const PMState = struct
{
    package_manager: *const pm.PackageManager,

    installed_packages: []const []const u8,
    requested_packages: []const []const u8,
};

fn getPMStates(stderr: *std.Io.Writer, recipe_dir: std.fs.Dir) !?[]PMState
{
    const allocator = arena.instance.allocator();
    var pmstates = std.ArrayList(PMState){};
    
    var dir_iter = recipe_dir.iterateAssumeFirstIteration();

    while (try dir_iter.next()) |child_dir|
    {
        if (child_dir.kind != std.fs.File.Kind.directory)
        {
            continue;
        }

        if (getPackageManager(child_dir)) |manager|
        {
            const requested_packages = try gatherPackages(
                try recipe_dir.openDir(child_dir.name, .{.iterate = true, .no_follow = true}));

            if (try manager.user_installed_cmd(stderr)) |installed|
            {
                try pmstates.append(allocator, .{
                    .package_manager = manager,
                    .installed_packages = installed,
                    .requested_packages = requested_packages
                });
            } 
            else
            {
                return null;
            }
        }
    }

    return pmstates.items;
}

fn applyPackages(_: *std.Io.Writer, stderr: *std.Io.Writer, recipe_dir: std.fs.Dir) !void
{
    const pmstates = try getPMStates(stderr, recipe_dir);

    for (pmstates orelse return) |pmstate|
    {
        const diff = try packageDiff(pmstate.installed_packages, pmstate.requested_packages);
        // now, we have to
        // 1. pass stdout to user and pass stdin to process
        // 2. detect when user decided to abort installation, in case some packages in recipe are broken

        if (!try pmstate.package_manager.uninstall_cmd(stderr, diff.toRemove) or
            !try pmstate.package_manager.remove_excessive_cmd(stderr) or
            !try pmstate.package_manager.install_cmd(stderr, diff.toAdd))
        {
            return;
        }
    }
}

fn previewPackages(stdout: *std.Io.Writer, stderr: *std.Io.Writer, packages_dir: std.fs.Dir) !void
{
    const pmstates = try getPMStates(stderr, packages_dir);
    for (pmstates orelse return) |pmstate|
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

pub const PMOperationType = enum {
    apply_packages,
    preview_packages
};

const Operation = struct {
    op_type: PMOperationType,
    function: *const fn (*std.Io.Writer, *std.Io.Writer, std.fs.Dir) anyerror!void
};

pub const operations = [_]Operation{
    .{
        .op_type = PMOperationType.apply_packages,
        .function = applyPackages
    },
    .{
        .op_type = PMOperationType.preview_packages,
        .function = previewPackages
    }
};

pub fn runPackageManagerOp(op_type: PMOperationType,
    stdout: *std.Io.Writer, stderr: *std.Io.Writer, recipe_dir: std.fs.Dir) !void
{
    inline for (operations) |operation|
    {
        if (operation.op_type == op_type)
        {
            try operation.function(stdout, stderr, recipe_dir);
            return;
        }
    }
}

