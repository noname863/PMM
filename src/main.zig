const std = @import("std");
const arena = @import("utils/simple_arena.zig");
const SimpleArena = arena.SimpleArena;

const stow_cmd = @import("stow/run_command.zig");
const package_cmd = @import("package_managers/run_command.zig");

fn getHomeDir(stderr: *std.Io.Writer) !?std.fs.Dir
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
    config_kind: ConfigKind,
};

const HelpOpDesc = struct
{
};

const operations = .{
    .{"--apply-home", .{StowOpDesc{.command_type = .apply, .config_kind = .home_cfg}},
        "Applies home dotfiles"},
    .{"--cleanup-home", .{StowOpDesc{.command_type = .cleanup, .config_kind = .home_cfg}},
        "Removes symlynks from home dotfiles"},
    .{"--force-apply-home", .{StowOpDesc{.command_type = .force_apply, .config_kind = .home_cfg}},
        "Applies home dotfiles, removes files which are on the way"},
    .{"--preview-apply-home", .{StowOpDesc{.command_type = .preview_apply, .config_kind = .home_cfg}},
        "Prints which symlinks are going to be created, and which files are going to be overwritten by --apply-home/--force-apply-home"},
    .{"--preview-cleanup-home", .{StowOpDesc{.command_type = .preview_cleanup, .config_kind = .home_cfg}},
        "Prings which symlinks are going to be deleted, and which symlinks are missing on --cleanup-home"},
    .{"--apply-root", .{StowOpDesc{.command_type = .apply, .config_kind = .root_cfg}},
        "Applies root dotfiles"},
    .{"--cleanup-root", .{StowOpDesc{.command_type = .cleanup, .config_kind = .root_cfg}},
        "Removes symlynks from root dotfiles"},
    .{"--force-apply-root", .{StowOpDesc{.command_type = .force_apply, .config_kind = .root_cfg}},
        "Removes symlynks from home dotfiles"},
    .{"--preview-apply-root", .{StowOpDesc{.command_type = .preview_apply, .config_kind = .root_cfg}},
        "Prints which symlinks are going to be created, and which files are going to be overwritten by --apply-rootcomptime /--force-apply-root"},
    .{"--preview-cleanup-root", .{StowOpDesc{.command_type = .preview_cleanup, .config_kind = .root_cfg}},
        "Prings which symlinks are going to be deleted, and which symlinks are missing on --cleanup-root"},
    .{"--apply-packages", .{package_cmd.PMOperationType.apply_packages},
        "Reads all packages which should be installed on the system from config, then makes sure " ++
        "that they are installed, their dependencies (recursively), and nothing else. Most likely will require sudo"},
    .{"--preview-packages", .{package_cmd.PMOperationType.preview_packages},
        "Shows which packages will be installed and removed if you use apply packages"},
    // .{"--apply-config", .{ StowOpDesc{.command_type = .apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .apply, .config_kind = .root_cfg} },
    //     "Applies all dotfiles"},
    // .{"--cleanup-config", .{StowOpDesc{.command_type = .cleanup, .config_kind = .home_cfg}, StowOpDesc{.command_type = .cleanup, .config_kind = .root_cfg}},
    //     "Removes symlynks from all dotfiles"},
    // .{"--force-apply-config", .{StowOpDesc{.command_type = .force_apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .force_apply, .config_kind = .root_cfg}},
    //     "Applies all dotfiles, removes files which are on the way"},
    // .{"--preview-apply-config", .{StowOpDesc{.command_type = .preview_apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .preview_apply, .config_kind = .root_cfg}},
    //     "Prints which symlinks are going to be created, and which files are going to be overwritten by --apply-config/--force-apply-config"},
    // .{"--preview-cleanup-config", .{StowOpDesc{.command_type = .preview_cleanup, .config_kind = .home_cfg}, StowOpDesc{.command_type = .preview_cleanup, .config_kind = .root_cfg}},
    //     "Prings which symlinks are going to be deleted, and which symlinks are missing on --cleanup-config"},
    // .{"--apply", .{package_cmd.PMOperationType.apply_packages, StowOpDesc{.command_type = .apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .apply, .config_kind = .root_cfg}},
    //     "Runs --apply-packages and --apply-config. It is not atomic"},
    // .{"--preview", .{package_cmd.PMOperationType.preview_packages, StowOpDesc{.command_type = .preview_apply, .config_kind = .home_cfg}, StowOpDesc{.command_type = .preview_apply, .config_kind = .root_cfg}},
    //     "Shows results of --preview-packages and --preview-apply-config"},
    .{"--help", .{HelpOpDesc{}}, "Prints this message"}
};

fn getPackagesDir(stderr: *std.Io.Writer) !?std.fs.Dir
{
    return std.fs.openDirAbsolute("/etc/pmm/packages", .{.iterate = true}) catch |err| {
        switch (err) {
            error.FileNotFound => try stderr.print("Folder /etc/pmm/config wasn't found, returning\n", .{}),
            error.NotDir => try stderr.print("/etc/pmm/config wasn't a folder\n", .{}),
            else => {return err; }
        }

        return null;
    };
}

fn getRootDotfiles(stderr: *std.Io.Writer) !?std.fs.Dir
{
    return std.fs.openDirAbsolute("/etc/pmm/config", .{.iterate = true}) catch |err| {
        switch (err) {
            error.FileNotFound => try stderr.print("Folder /etc/pmm/config wasn't found, returning\n", .{}),
            error.NotDir => try stderr.print("/etc/pmm/config wasn't a folder\n", .{}),
            else => {return err; }
        }

        return null;
    };
}

fn getHomeDotfiles(stderr: *std.Io.Writer, home_dir: std.fs.Dir) !?std.fs.Dir
{
    const config_data = if (std.posix.getenv("XDG_CONFIG_HOME")) |config_dir_path|
        .{std.fs.openDirAbsolute(config_dir_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => try stderr.print("Folder {s} which was in XDG_CONFIG_HOME wasn't found, returning\n", .{config_dir_path}),
                error.NotDir => try stderr.print("XDG_CONFIG_HOME had path {s}, which wasn't a folder\n", .{config_dir_path}),
                else => {return err; }
            }

            return null;
        }, config_dir_path}
    else
        .{home_dir.openDir(".config", .{}) catch |err|
        {
            switch (err) {
                error.FileNotFound => try stderr.print("XDG_CONFIG_HOME wasn't found, and .config in home directory as well\n", .{}),
                error.NotDir => try stderr.print("XDG_CONFIG_HOME wasn't found, and .config wasn't a directory\n", .{}),
                else => {return err; }
            }

            return null;
        }, "$HOME/.config"};

    return config_data.@"0".openDir("pmm", .{ .iterate = true}) catch |err| {
        switch (err) {
            error.FileNotFound => try stderr.print("pmm folder wasn't found in config folder {s}\n", .{config_data.@"1"}),
            error.NotDir => try stderr.print("pmm wasn't a folder, in a config folder {s}\n", .{config_data.@"1"}),
            else => {return err; }
        }

        return null;
    };
}

fn printHelp(stdout: *std.Io.Writer) !void
{
    try stdout.print("Usage: pmm <Operation> [Package name]\n\n" ++
        "Configuration folders:\n" ++
        "  Packages lists at \"/etc/pmm/packages\"\n" ++
        "  Root dotfiles at \"/etc/pmm/config\"\n" ++
        "  Home dotfiles at \"$HOME/$XDG_CONFIG_HOME/pmm\", or at \"$HOME/.config/pmm\" if $XDG_CONFIG_HOME wasn't found\n\n" ++
        "Operations:\n", .{});

    
    inline for (operations) |operation|
    {
        const number_of_spaces = 40 - operation.@"0".len;
        const spaces = " " ** 40;
        try stdout.print("  {s}{s}{s}\n", .{operation.@"0", spaces[0..number_of_spaces], operation.@"2"});
    }
}

const WrongOperandReason = enum
{
    complex_op,
    package_mgr
};

fn getWrongOperandReason(comptime operation: type) ?WrongOperandReason
{
    switch (@typeInfo(operation))
    {
        .@"struct" => |str| {
            if (str.fields.len > 1)
            {
                return WrongOperandReason.complex_op;
            }
            return if (str.fields[0].type == StowOpDesc) null else WrongOperandReason.package_mgr;
        },
        else => { @compileError(""); }
    }
}

fn doOperations(op_flag: [*:0]const u8, opt_operand: ?[*:0]const u8,
    stdout: *std.io.Writer, stderr: *std.io.Writer) !void
{
    inline for (operations) |operation|
    {
        if (std.mem.orderZ(u8, operation.@"0", op_flag) == .eq)
        {
            inline for (operation.@"1") |command|
            {
                if (opt_operand != null)
                {
                    const opt_wrong_op_reason = comptime getWrongOperandReason(@TypeOf(operation.@"1"));
                    if (opt_wrong_op_reason) |wrong_op_reason|
                    {
                        try stderr.print(switch (wrong_op_reason)
                        {
                            .complex_op => "Specifying package makes little sence for operation which has multiple steps. Try to use \"home\" and \"root\" versions\n",
                            .package_mgr => "Specifying package makes no sence for package manager operation. If you want to install package, add it to config and run apply\n"
                        }, .{});

                        return;
                    }
                }
                if (@TypeOf(command) == StowOpDesc)
                {
                    var opt_deploy_dir: ?std.fs.Dir = undefined;
                    var opt_config_dir: ?std.fs.Dir = undefined;
                    if (command.config_kind == .home_cfg)
                    {
                        opt_deploy_dir = try getHomeDir(stderr);
                        opt_config_dir = if (opt_deploy_dir) |deploy_dir| try getHomeDotfiles(stderr, deploy_dir) else null;
                    }
                    else
                    {
                        opt_deploy_dir = try getRootDir();
                        opt_config_dir = try getRootDotfiles(stderr);
                    }
                    if (opt_config_dir == null or opt_config_dir == null)
                    {
                        return;
                    }

                    if (opt_operand) |operand|
                    {
                        const package_dir = opt_config_dir.?.openDirZ(operand, .{.iterate = true, .no_follow = true}) catch |err| {
                            switch (err)
                            {
                                error.FileNotFound => { try stderr.print("Package with name {s} wasn't found\n", .{operand}); return; },
                                error.NotDir => {
                                    var config_dir_storage: [std.fs.max_path_bytes]u8 = undefined;
                                    const config_dir_name = try opt_config_dir.?.realpath(".", &config_dir_storage);
                                    try stderr.print("Instead for folder in {s} for package {s}, there was a file with a same name\n", .{config_dir_name, operand});
                                    return; },
                                else => { return err; }
                            }
                        };
                        try stow_cmd.runStowCommandSpecific(command.command_type, package_dir, opt_deploy_dir.?, stdout, stderr);
                    }
                    else
                    {
                        try stow_cmd.runStowCommandForAll(command.command_type, opt_config_dir.?, opt_deploy_dir.?, stdout, stderr);
                    }
                }
                else if (@TypeOf(command) == package_cmd.PMOperationType)
                {
                    const package_dir = try getPackagesDir(stderr) orelse return;
                    try package_cmd.runPackageManagerOp(command, stdout, stderr, package_dir);
                }
                else if (@TypeOf(command) == HelpOpDesc)
                {
                    try printHelp(stdout);
                }
            }

            return;
        }
    }

    try printHelp(stdout);
    try stdout.print("\nUnknown operation {s}\n", .{op_flag});
}

fn applyHome(stdout: *const std.Io.Writer, stderr: *const std.Io.Writer, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.apply, packages_dir, deploy_dir, stdout, stderr);
    }
    // try iterateConfigFromHome(StowContext{.stderr = &stderr, .overwrite = overwrite}, packages_dir, stowSameFunc, stowNotExists);
}

fn cleanupHome(stdout: *const std.Io.Writer, stderr: *const std.Io.Writer, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.cleanup, packages_dir, deploy_dir, stdout, stderr);
    }
}

fn previewApplyHome(stdout: *const std.Io.Writer, stderr: *const std.Io.Writer, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.preview_apply, packages_dir, deploy_dir, stdout, stderr);
    }
}

fn previewCleanupHome(stdout: *const std.Io.Writer, stderr: *const std.Io.Writer, packages_dir: std.fs.Dir) !void
{
    if (try getHomeDir(stderr)) |deploy_dir|
    {
        // const ptr: [*:0]const u8 = @ptrCast("--apply-home");
        try stow_cmd.runStowCommand(stow_cmd.CommandType.preview_cleanup, packages_dir, deploy_dir, stdout, stderr);
    }
}

fn processAccessDenied(stdout: *std.Io.Writer, err: anyerror) !void
{
    if (err == error.AccessDenied)
    {
        try stdout.print("Access Denied when trying to do operation." ++
            " Consider running tool with sudo.\n", .{});
    }
    else
    {
        return err;
    }
}

var stdout_buf: [4096]u8 = undefined;
var stderr_buf: [4096]u8 = undefined;

pub fn main() !void {
    // TODO: add a lot of error handling. For now if something goes wrong
    // I will recieve debug messages, and stacktrace, but need to consider
    // something nicer for stuff which will face user
    defer arena.instance.deinit();

    var stdout_file = std.fs.File.stdout().writer(&stdout_buf);
    var stdout = &stdout_file.interface;
    var stderr_file = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_file.interface;

    // don't forget to flush)
    defer (stdout.flush() catch {});
    defer (stderr.flush() catch {});

    if (std.os.argv.len < 2)
    {
        try stdout.print("Too little command line arguments\n\n", .{});

        try printHelp(stdout);
        return;
    }

    const operand = if (std.os.argv.len > 2) std.os.argv[2] else null;

    doOperations(std.os.argv[1], operand, stdout, stderr) catch |err| {
        try processAccessDenied(stdout, err);
    };
}

