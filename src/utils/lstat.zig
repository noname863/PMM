const std = @import("std");

pub fn lstat(dir: std.fs.Dir, path: []const u8, follow: bool) std.fs.Dir.StatFileError!std.fs.File.Stat
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

