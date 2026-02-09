//! Cross-platform dynamic library loader.
//!
//! On Windows, uses LoadLibraryW/GetProcAddress/FreeLibrary directly
//! since std.DynLib does not support Windows. On other platforms,
//! delegates to std.DynLib.

const std = @import("std");
const builtin = @import("builtin");

pub const DynLib = if (builtin.os.tag == .windows) WinDynLib else std.DynLib;

const WinDynLib = struct {
    handle: std.os.windows.HMODULE,

    const windows = std.os.windows;

    pub fn open(path: []const u8) error{FileNotFound}!WinDynLib {
        var path_w: [260]u16 = undefined;
        const len = std.unicode.wtf8ToWtf16Le(&path_w, path) catch return error.FileNotFound;
        if (len >= path_w.len) return error.FileNotFound;
        path_w[len] = 0;
        const handle = windows.kernel32.LoadLibraryW(@ptrCast(&path_w)) orelse return error.FileNotFound;
        return .{ .handle = handle };
    }

    pub fn lookup(self: *WinDynLib, comptime T: type, name: [:0]const u8) ?T {
        const ptr = windows.kernel32.GetProcAddress(self.handle, @ptrCast(name.ptr)) orelse return null;
        return @ptrCast(ptr);
    }

    pub fn close(self: *WinDynLib) void {
        _ = windows.kernel32.FreeLibrary(self.handle);
    }
};
