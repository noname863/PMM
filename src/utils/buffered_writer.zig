const std = @import("std");

pub const BufferedFileWriter = std.io.BufferedWriter(4096, std.fs.File.Writer).Writer;
// const BufferedFileWriter = @TypeOf(std.io.bufferedWriter(std.io.getStdOut().writer())).Writer;

