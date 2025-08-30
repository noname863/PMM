const std = @import("std");

pub fn SameFileFunc(ContextType: type) type
{
    return *const fn(ContextType, std.fs.Dir, std.fs.Dir, std.fs.Dir.Entry, std.fs.Dir.Stat) anyerror!void; 
}

pub fn FileNotExistsFunc(ContextType: type) type
{
    return *const fn(ContextType, std.fs.Dir, std.fs.Dir, std.fs.Dir.Entry) anyerror!void; 
}

