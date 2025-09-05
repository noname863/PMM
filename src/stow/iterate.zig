const std = @import("std");
const functions = @import("functions.zig");
const SameFileFunc = functions.SameFileFunc;
const FileNotExistsFunc = functions.FileNotExistsFunc;

const DirKind = std.fs.Dir.Entry.Kind;

const lstat = @import("../utils/lstat.zig").lstat;

pub fn iterateSpecificConfig(context: anytype, package_dir: std.fs.Dir, deploy_dir: std.fs.Dir,
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

pub fn iterateConfig(context: anytype, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir,
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
