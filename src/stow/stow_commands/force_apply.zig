const apply = @import("apply.zig");
const BufferedFileWriter = @import("../../utils/buffered_writer.zig").BufferedFileWriter;

pub const Context = apply.Context;

pub const same = apply.same;
pub const notExists = apply.notExists;

pub fn createContext(_: *const BufferedFileWriter, stderr: *const BufferedFileWriter) Context
{
    return .{
        .stderr = stderr,
        .overwrite = true,
    };
}

