const std = @import("std");
const arena = @import("../utils/simple_arena.zig");


const parsePackages = @import("parse_packages.zig").parsePackages;
const attachedProcess = @import("attached_process.zig");
const runAttachedProcess = attachedProcess.runAttachedProcess;
const stringCompare = @import("../utils/string_compare.zig").stringCompare;

const AttachedCmdFunction = fn(*std.Io.Writer) anyerror!bool;
const AttachedCmdWithArgs = fn(*std.Io.Writer, []const []const u8) anyerror!bool;

fn attachedCmdFunc(comptime args: anytype, comptime op_name: []const u8) AttachedCmdFunction
{
    const Res = struct {
        fn func(stderr: *std.Io.Writer) !bool
        {
            return try runAttachedProcess(stderr, &args, op_name);
        }
    };

    return Res.func;
}

fn attachedCmdWithArgs(comptime args: anytype, comptime op_name: []const u8) AttachedCmdWithArgs
{
    const Res = struct {
        fn func(stderr: *std.Io.Writer, additional_args: []const []const u8) !bool
        {
            if (additional_args.len == 0)
            {
                return true;
            }
            // const fullArgs = std.ArrayList([]const u8).init(arena.instance.allocator());
            var full_args: [][]const u8 = try arena.instance.allocator().alloc([]const u8, args.len + additional_args.len);
            @memcpy(full_args[0..args.len], &args);
            @memcpy(full_args[args.len..(args.len + additional_args.len)], additional_args);

            return try runAttachedProcess(stderr, full_args, op_name);
        }
    };

    return Res.func;
}

const GetCmdFunction = fn(*std.Io.Writer) anyerror!?[][]const u8;

fn getCmdFunction(comptime args: anytype, comptime op_name: []const u8) GetCmdFunction
{
    const Res = struct
    {
        fn func(stderr: *std.Io.Writer) !?[][]const u8{
            const allocator = arena.instance.allocator();

            var packages = std.ArrayList([]const u8){};

            const result = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &args,
            });

            if (!try attachedProcess.checkProcessFailure(stderr, op_name, result.term))
            {
                return null;
            }

            try parsePackages(&packages, result.stdout);

            std.mem.sortUnstable([]const u8, packages.items, {}, stringCompare);

            return packages.items;
        }
    };

    return Res.func;
}

pub const PackageManager = struct
{
    name: []const u8,
    user_installed_cmd: *const GetCmdFunction,
    remove_excessive_cmd: *const AttachedCmdFunction,
    uninstall_cmd: *const AttachedCmdWithArgs,
    install_cmd: *const AttachedCmdWithArgs,

    fn init(
        name: []const u8,
        user_installed_cmd: anytype,
        remove_excessive_cmd: anytype,
        uninstall_cmd: anytype,
        install_cmd: anytype) PackageManager
    {
        const args = .{
            .{user_installed_cmd, "user_installed_cmd", "Get Installed", getCmdFunction, GetCmdFunction},
            .{remove_excessive_cmd, "remove_excessive_cmd", "Remove Excessive", attachedCmdFunc, AttachedCmdFunction},
            .{uninstall_cmd, "uninstall_cmd", "Uninstall", attachedCmdWithArgs, AttachedCmdWithArgs},
            .{install_cmd, "install_cmd", "Install", attachedCmdWithArgs, AttachedCmdWithArgs}
        };
        var res: PackageManager = undefined;
        res.name = name;

        inline for (args) |arg|
        {
            if (@TypeOf(arg.@"0") == arg.@"4" or @TypeOf(arg.@"0") == *const arg.@"4")
            {
                @field(res, arg.@"1") = arg.@"0";
            }
            else
            {
                @field(res, arg.@"1") = arg.@"3"(arg.@"0", arg.@"2");
            }
        }

        return res;
    }
};

fn removeExcessiveFn(comptime pacman_like_pm: []const u8) *const fn(*std.Io.Writer) anyerror!bool
{
    const ResType = struct
    {
        fn pacmanRemoveExcessive(stderr: *std.Io.Writer) anyerror!bool
        {
            const pacman_find_orphans = [_][]const u8{pacman_like_pm, "-Qdtq"};

            const allocator = arena.instance.allocator();

            const result = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &pacman_find_orphans,
            });

            if (switch (result.term)
                {
                    .Exited => |code| (code != 0) and (code != 1 or result.stdout.len != 0),
                    else => true,
                })
            {
                try stderr.print("Error: {s} -Qdtq, which is supposed to return " ++
                    "all unused packages failed. returning early \n", .{pacman_like_pm});
                return false;
            }

            if (result.stdout.len == 0)
            {
                return true;
            }

            var packages = std.ArrayList([]const u8){};
            try packages.appendSlice(arena.allocator, &[_][]const u8{"pacman", "-Rcns"});
            try parsePackages(&packages, result.stdout);

            if (packages.items.len == 2)
            {
                return true;
            }
            else
            {
                return try runAttachedProcess(stderr, packages.items, "Remove excessive");
            }
        }
    };

    return ResType.pacmanRemoveExcessive;
}


pub const package_managers = [_]PackageManager{
    PackageManager.init(
        "dnf",
        [_][]const u8{"dnf", "repoquery", "--userinstalled", "--queryformat=%{name}\n"},
        [_][]const u8{"dnf", "autoremove"},
        [_][]const u8{"dnf", "remove"},
        [_][]const u8{"dnf", "install"}
    ),
    PackageManager.init(
        "pacman",
        [_][]const u8{"pacman", "-Qeq"},
        removeExcessiveFn("pacman"),
        [_][]const u8{"pacman", "-Rcns"},
        [_][]const u8{"pacman", "-Suy"}
    ),
    PackageManager.init(
        "paru",
        [_][]const u8{"paru", "-Qeq"},
        removeExcessiveFn("paru"),
        [_][]const u8{"paru", "-Rcns"},
        [_][]const u8{"paru", "-Suy"}
    )
};

