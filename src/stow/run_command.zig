const std = @import("std");

const DirKind = std.fs.Dir.Entry.Kind;
const BufferedFileWriter = @import("../utils/buffered_writer.zig").BufferedFileWriter;

const iterate = @import("iterate.zig");

pub const CommandType = enum
{
    apply,
    cleanup,
    force_apply,
    preview_apply,
    preview_cleanup
};

const commands = .{
    .{
        CommandType.apply,
        @import("stow_commands/apply.zig")
    },
    .{
        CommandType.cleanup,
        @import("stow_commands/cleanup.zig")
    },
    .{
        CommandType.force_apply,
        @import("stow_commands/force_apply.zig")
    },
    .{
        CommandType.preview_apply,
        @import("stow_commands/preview_apply.zig")
    },
    .{
        CommandType.preview_cleanup,
        @import("stow_commands/preview_cleanup.zig")
    }
};

pub fn runStowCommandForAll(command_type: CommandType, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir,
    stdout: *const BufferedFileWriter, stderr: *const BufferedFileWriter) !void
{
    inline for (commands) |command|
    {
        if (command_type == command.@"0")
        {
            const context = command.@"1".createContext(stdout, stderr);

            try iterate.iterateConfig(context, config_dir, deploy_dir, command.@"1".same, command.@"1".notExists);
        }
    }
}

pub fn runStowCommandSpecific(command_type: CommandType, package_dir: std.fs.Dir, deploy_dir: std.fs.Dir,
    stdout: *const BufferedFileWriter, stderr: *const BufferedFileWriter) !void
{
    
    inline for (commands) |command|
    {
        if (command_type == command.@"0")
        {
            const context = command.@"1".createContext(stdout, stderr);

            try iterate.iterateSpecificConfig(context, package_dir, deploy_dir, command.@"1".same, command.@"1".notExists);
        }
    }
}
