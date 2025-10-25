const std = @import("std");
const DirKind = std.fs.Dir.Entry.Kind;

pub const Context = struct
{
    stderr: *std.Io.Writer,
    overwrite: bool
};

fn stowMakeLink(config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    // var path: [std.fs.max_path_bytes]u8 = undefined;
    var path: [std.fs.max_path_bytes]u8 = undefined;
    const path_slice = try config_dir.realpath(file.name, &path);
    try deploy_dir.symLink(path_slice, file.name, .{.is_directory = (file.kind == DirKind.directory)});
}

pub fn same(context: Context, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry, _: std.fs.Dir.Stat) !void
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

pub fn notExists(_: Context, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    try stowMakeLink(config_dir, deploy_dir, file);
}

pub fn createContext(_: *std.Io.Writer, stderr: *std.Io.Writer) Context
{
    return .{
        .stderr = stderr,
        .overwrite = false,
    };
}

