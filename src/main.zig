const std = @import("std");
const arena = @import("utils/simple_arena.zig");
const SimpleArena = arena.SimpleArena;

const BufferedFileWriter = @import("utils/buffered_writer.zig").BufferedFileWriter;

const stow_cmd = @import("stow/run_command.zig");
const package_cmd = @import("package_managers/run_command.zig");

fn getHomeDir(stderr: *const BufferedFileWriter) !?std.fs.Dir
{
    if (std.posix.getenv("HOME")) |home|
    {
        return try std.fs.openDirAbsolute(home, .{.iterate = false, .no_follow = true});
        // const deploy_dir
        // try iterateConfig(context, config_dir, deploy_dir, same_name_func, not_exists_func);
    }
    else
    {
        try stderr.print("Home not found! Stopping...\n", .{});
        return null;
    }
}

fn getRootDir() !std.fs.Dir
{
    return try std.fs.openDirAbsolute("/", .{.iterate = false, .no_follow = true});
}

const ConfigKind = enum
{
    home_cfg,
    root_cfg
};

const StowOpDesc = struct
{
    command_type: stow_cmd.CommandType,
    config_kind: ConfigKind
};

const operations = .{
    .{"--apply-home", .{StowOpDesc{.command_type = .apply, .config_kind = .home_cfg}}},
    .{"--cleanup-home", .{StowOpDesc{.command_type = .cleanup, .config_kind = .home_cfg}}},
    .{"--force-apply-home", .{StowOpDesc{.command_type = .force_apply, .config_kind = .home_cfg}}},
    .{"--preview-apply-home", .{StowOpDesc{.command_type = .preview_apply, .config_kind = .home_cfg}}},
    .{"--preview-cleanup-home", .{StowOpDesc{.command_type = .preview_cleanup, .config_kind = .home_cfg}}},
    .{"--apply-root", .{StowOpDesc{.command_type = .apply, .config_kind = .root_cfg}}},
    .{"--cleanup-root", .{StowOpDesc{.command_type = .cleanup, .config_kind = .root_cfg}}},
    .{"--force-apply-root", .{StowOpDesc{.command_type = .force_apply, .config_kind = .root_cfg}}},
    .{"--preview-apply-root", .{StowOpDesc{.command_type = .preview_apply, .config_kind = .root_cfg}}},
    .{"--preview-cleanup-root", .{StowOpDesc{.command_type = .preview_cleanup, .config_kind = .root_cfg}}},
    .{"--apply-packages", .{package_cmd.PMOperationType.apply_packages}},
    .{"--preview-packages", .{package_cmd.PMOperationType.preview_packages}},
    .{"--apply-config", .{StowOpDesc{.command_type = .apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .apply, .config_kind = .root_cfg}}},
    .{"--cleanup-config", .{StowOpDesc{.command_type = .cleanup, .config_kind = .home_cfg}, StowOpDesc{.command_type = .cleanup, .config_kind = .root_cfg}}},
    .{"--force-apply-config", .{StowOpDesc{.command_type = .force_apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .force_apply, .config_kind = .root_cfg}}},
    .{"--preview-apply-config", .{StowOpDesc{.command_type = .preview_apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .preview_apply, .config_kind = .root_cfg}}},
    .{"--preview-cleanup-config", .{StowOpDesc{.command_type = .preview_cleanup, .config_kind = .home_cfg}, StowOpDesc{.command_type = .preview_cleanup, .config_kind = .root_cfg}}},
    .{"--apply", .{package_cmd.PMOperationType.apply_packages, StowOpDesc{.command_type = .apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .apply, .config_kind = .root_cfg}}},
    .{"--preview", .{package_cmd.PMOperationType.preview_packages, StowOpDesc{.command_type = .preview_apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .preview_apply, .config_kind = .root_cfg}}}
};

fn doOperations(op_flag: [*:0]const u8, stdout: *const BufferedFileWriter, stderr: *const BufferedFileWriter, recipe_dir: std.fs.Dir) !void
{
    inline for (operations) |operation|
    {
        if (std.mem.orderZ(u8, operation.@"0", op_flag) == .eq)
        {
            inline for (operation.@"1") |command|
            {
                if (@TypeOf(command) == StowOpDesc)
                {
                    var deploy_dir: ?std.fs.Dir = undefined;
                    var packages_dir_name: []const u8 = undefined;
                    if (command.config_kind == .home_cfg)
                    {
                        deploy_dir = try getHomeDir(stderr);
                        packages_dir_name = "home_config";
                    }
                    else
                    {
                        deploy_dir = try getRootDir();
                        packages_dir_name = "root_config";
                    }
                    if (deploy_dir == null)
                    {
                        return;
                    }
                    const packages_dir = recipe_dir.openDir(packages_dir_name, .{.iterate = true, .no_follow = true}) catch |err|
                    {
                        if (err == error.FileNotFound)
                        {
                            // not found for packages is not an error, that means that there is nothing to deploy
                            try stderr.print("No {s} in recipe directory, skipping...\n", .{packages_dir_name});
                            return;
                        }
                        return err;
                    };
                    try stow_cmd.runStowCommand(command.command_type, packages_dir, deploy_dir.?, stdout, stderr);
                }
                else if (@TypeOf(command) == package_cmd.PMOperationType)
                {
                    const package_dir = try recipe_dir.openDir("packages", .{.iterate = true, .no_follow = true});
                    try package_cmd.runPackageManagerOp(command, stdout, stderr, package_dir);
                }
            }

            return;
        }
    }

    try stdout.print("Unknown argument\n", .{});
}

fn applyHome(stdout: *const BufferedFileWriter, stderr: *const BufferedFileWriter, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.apply, packages_dir, deploy_dir, stdout, stderr);
    }
    // try iterateConfigFromHome(StowContext{.stderr = &stderr, .overwrite = overwrite}, packages_dir, stowSameFunc, stowNotExists);
}

fn cleanupHome(stdout: *const BufferedFileWriter, stderr: *const BufferedFileWriter, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.cleanup, packages_dir, deploy_dir, stdout, stderr);
    }
}

fn previewApplyHome(stdout: *const BufferedFileWriter, stderr: *const BufferedFileWriter, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.preview_apply, packages_dir, deploy_dir, stdout, stderr);
    }
}

fn previewCleanupHome(stdout: *const BufferedFileWriter, stderr: *const BufferedFileWriter, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.preview_cleanup, packages_dir, deploy_dir, stdout, stderr);
    }
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
    defer arena.instance.deinit();

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
        try stdout.print("Command argument which should've been recipe dir wasn't a directory\n", .{});
        return;
    };

    doOperations(std.os.argv[2], &stdout, &stderr, recipe_dir) catch |err| {
        try processAccessDenied(stdout, err);
    };
}

