const std = @import("std");


const DirKind = std.fs.Dir.Entry.Kind;

pub const Context = struct
{
    stderr: *std.Io.Writer
};

pub fn same(context: Context, config_dir: std.fs.Dir, deploy_dir: std.fs.Dir, file: std.fs.Dir.Entry, stat: std.fs.Dir.Stat) !void
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

pub fn notExists(context: Context,
    config_dir: std.fs.Dir, _: std.fs.Dir, file: std.fs.Dir.Entry) !void
{
    var package_path: [std.fs.max_path_bytes]u8 = undefined;
    const package_path_slice = try config_dir.realpath(file.name, &package_path);
    try context.stderr.print("Warning: file which should correspond to the {s} wasn't found\n", .{package_path_slice});
}

pub fn createContext(_: *std.Io.Writer, stderr: *std.Io.Writer) Context
{
    return .{
        .stderr = stderr
    };
}

