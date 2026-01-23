const std = @import("std");
const builtin = @import("builtin");

/// Zstd compression wrapper for Hytale packet compression
/// 60 packets in the registry are marked compressed: true and require Zstd
/// Uses dynamic linking to libzstd/zstd.dll

pub const ZstdError = error{
    CompressionFailed,
    DecompressionFailed,
    OutputTooSmall,
    InvalidData,
    OutOfMemory,
    LibraryNotFound,
};

/// Compression level options (matches ZSTD compression levels)
pub const CompressionLevel = enum(c_int) {
    fast = 1,
    default = 3,
    better = 6,
    best = 9,
    max = 19,
};

// Zstd library function types
const ZSTD_compressFn = *const fn (
    dst: [*]u8,
    dst_capacity: usize,
    src: [*]const u8,
    src_size: usize,
    compression_level: c_int,
) callconv(.c) usize;

const ZSTD_decompressFn = *const fn (
    dst: [*]u8,
    dst_capacity: usize,
    src: [*]const u8,
    compressed_size: usize,
) callconv(.c) usize;

const ZSTD_isErrorFn = *const fn (code: usize) callconv(.c) c_uint;
const ZSTD_getErrorNameFn = *const fn (code: usize) callconv(.c) [*:0]const u8;
const ZSTD_compressBoundFn = *const fn (src_size: usize) callconv(.c) usize;
const ZSTD_getFrameContentSizeFn = *const fn (src: [*]const u8, src_size: usize) callconv(.c) u64;

/// Zstd library wrapper with lazy loading
pub const ZstdLib = struct {
    dll: ?std.DynLib,
    compress_fn: ?ZSTD_compressFn,
    decompress_fn: ?ZSTD_decompressFn,
    is_error_fn: ?ZSTD_isErrorFn,
    get_error_name_fn: ?ZSTD_getErrorNameFn,
    compress_bound_fn: ?ZSTD_compressBoundFn,
    frame_content_size_fn: ?ZSTD_getFrameContentSizeFn,

    var global_instance: ?ZstdLib = null;

    const Self = @This();

    /// Get or initialize the global Zstd library instance
    pub fn getInstance() !*ZstdLib {
        if (global_instance) |*inst| {
            if (inst.dll != null) return inst;
        }

        global_instance = try init();
        return &global_instance.?;
    }

    fn init() !ZstdLib {
        const dll_names = switch (builtin.os.tag) {
            .windows => [_][]const u8{ "zstd.dll", "libzstd.dll" },
            .macos => [_][]const u8{ "libzstd.dylib", "libzstd.1.dylib" },
            else => [_][]const u8{ "libzstd.so", "libzstd.so.1" },
        };

        var dll: ?std.DynLib = null;
        for (dll_names) |name| {
            dll = std.DynLib.open(name) catch continue;
            if (dll != null) break;
        }

        if (dll == null) {
            std.log.warn("Zstd library not found. Compression will be disabled.", .{});
            std.log.warn("To enable compression, install zstd and ensure zstd.dll is in PATH", .{});
            return Self{
                .dll = null,
                .compress_fn = null,
                .decompress_fn = null,
                .is_error_fn = null,
                .get_error_name_fn = null,
                .compress_bound_fn = null,
                .frame_content_size_fn = null,
            };
        }

        var self = Self{
            .dll = dll,
            .compress_fn = dll.?.lookup(ZSTD_compressFn, "ZSTD_compress"),
            .decompress_fn = dll.?.lookup(ZSTD_decompressFn, "ZSTD_decompress"),
            .is_error_fn = dll.?.lookup(ZSTD_isErrorFn, "ZSTD_isError"),
            .get_error_name_fn = dll.?.lookup(ZSTD_getErrorNameFn, "ZSTD_getErrorName"),
            .compress_bound_fn = dll.?.lookup(ZSTD_compressBoundFn, "ZSTD_compressBound"),
            .frame_content_size_fn = dll.?.lookup(ZSTD_getFrameContentSizeFn, "ZSTD_getFrameContentSize"),
        };

        if (self.compress_fn == null or self.decompress_fn == null or self.is_error_fn == null) {
            std.log.err("Failed to find required Zstd functions", .{});
            self.deinit();
            return error.LibraryNotFound;
        }

        std.log.info("Zstd library loaded successfully", .{});
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.dll) |*dll| {
            dll.close();
            self.dll = null;
        }
    }

    pub fn isAvailable(self: *const Self) bool {
        return self.dll != null and self.compress_fn != null and self.decompress_fn != null;
    }

    fn isError(self: *const Self, code: usize) bool {
        if (self.is_error_fn) |is_err| {
            return is_err(code) != 0;
        }
        // Fallback: check if high bit is set (typical error convention)
        return @as(isize, @bitCast(code)) < 0;
    }

    fn getErrorName(self: *const Self, code: usize) []const u8 {
        if (self.get_error_name_fn) |get_err| {
            const name = get_err(code);
            return std.mem.span(name);
        }
        return "unknown error";
    }
};

/// Decompress Zstd-compressed data
/// Returns owned memory that must be freed by the caller
pub fn decompress(allocator: std.mem.Allocator, compressed_data: []const u8, max_output_size: usize) ![]u8 {
    const lib = try ZstdLib.getInstance();
    if (!lib.isAvailable()) {
        return ZstdError.LibraryNotFound;
    }

    // Try to get frame content size first
    var output_size = max_output_size;
    if (lib.frame_content_size_fn) |get_size| {
        const size = get_size(compressed_data.ptr, compressed_data.len);
        // ZSTD_CONTENTSIZE_UNKNOWN = 0xFFFFFFFFFFFFFFFF
        // ZSTD_CONTENTSIZE_ERROR = 0xFFFFFFFFFFFFFFFE
        if (size < 0xFFFFFFFFFFFFFFFE and size <= max_output_size) {
            output_size = @intCast(size);
        }
    }

    // Allocate output buffer
    const output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    // Decompress
    const result = lib.decompress_fn.?(
        output.ptr,
        output.len,
        compressed_data.ptr,
        compressed_data.len,
    );

    if (lib.isError(result)) {
        std.log.err("Zstd decompression error: {s}", .{lib.getErrorName(result)});
        return ZstdError.DecompressionFailed;
    }

    // Resize to actual decompressed size if smaller
    if (result < output.len) {
        return allocator.realloc(output, result) catch output[0..result];
    }

    return output;
}

/// Compress data using Zstd
/// Returns owned memory that must be freed by the caller
pub fn compress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return compressWithLevel(allocator, data, .default);
}

/// Compress data using Zstd with specified compression level
/// Returns owned memory that must be freed by the caller
pub fn compressWithLevel(allocator: std.mem.Allocator, data: []const u8, level: CompressionLevel) ![]u8 {
    const lib = try ZstdLib.getInstance();
    if (!lib.isAvailable()) {
        return ZstdError.LibraryNotFound;
    }

    // Calculate max compressed size
    var max_size = data.len + (data.len >> 7) + 128; // Conservative estimate
    if (lib.compress_bound_fn) |bound| {
        max_size = bound(data.len);
    }

    // Allocate output buffer
    const output = try allocator.alloc(u8, max_size);
    errdefer allocator.free(output);

    // Compress
    const result = lib.compress_fn.?(
        output.ptr,
        output.len,
        data.ptr,
        data.len,
        @intFromEnum(level),
    );

    if (lib.isError(result)) {
        std.log.err("Zstd compression error: {s}", .{lib.getErrorName(result)});
        return ZstdError.CompressionFailed;
    }

    // Resize to actual compressed size
    if (result < output.len) {
        return allocator.realloc(output, result) catch output[0..result];
    }

    return output;
}

/// Calculate the maximum compressed size for a given input size
pub fn compressBound(src_size: usize) usize {
    if (ZstdLib.getInstance()) |lib| {
        if (lib.compress_bound_fn) |bound| {
            return bound(src_size);
        }
    } else |_| {}

    // Fallback estimate
    return src_size + (src_size >> 7) + 128;
}

/// Check if Zstd library is available
pub fn isAvailable() bool {
    if (ZstdLib.getInstance()) |lib| {
        return lib.isAvailable();
    } else |_| {
        return false;
    }
}

/// Check if data appears to be Zstd compressed (magic number check)
pub fn isZstdCompressed(data: []const u8) bool {
    // Zstd magic number: 0xFD2FB528 (little-endian)
    if (data.len < 4) return false;

    return data[0] == 0x28 and
        data[1] == 0xB5 and
        data[2] == 0x2F and
        data[3] == 0xFD;
}

// Tests - only run if library is available
test "isZstdCompressed magic number check" {
    // Valid Zstd magic number (little-endian 0xFD2FB528)
    const valid_header = [_]u8{ 0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x00 };
    try std.testing.expect(isZstdCompressed(&valid_header));

    // Invalid data
    const invalid = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    try std.testing.expect(!isZstdCompressed(&invalid));

    // Too short
    const short = [_]u8{ 0x28, 0xB5 };
    try std.testing.expect(!isZstdCompressed(&short));
}

test "compress and decompress round trip" {
    // Skip test if library not available
    if (!isAvailable()) {
        std.log.warn("Zstd library not available, skipping test", .{});
        return;
    }

    const allocator = std.testing.allocator;
    const original = "Hello, Hytale! This is a test message for Zstd compression.";

    // Compress
    const compressed = try compress(allocator, original);
    defer allocator.free(compressed);

    // Verify it looks compressed (has magic number)
    try std.testing.expect(isZstdCompressed(compressed));

    // Decompress
    const decompressed = try decompress(allocator, compressed, 1024);
    defer allocator.free(decompressed);

    // Verify round trip
    try std.testing.expectEqualStrings(original, decompressed);
}

test "compress with different levels" {
    // Skip test if library not available
    if (!isAvailable()) {
        std.log.warn("Zstd library not available, skipping test", .{});
        return;
    }

    const allocator = std.testing.allocator;
    const original = "Test data " ** 100; // Repetitive data compresses well

    // Test fast compression
    const fast = try compressWithLevel(allocator, original, .fast);
    defer allocator.free(fast);

    // Test best compression
    const best = try compressWithLevel(allocator, original, .best);
    defer allocator.free(best);

    // Best should be smaller or equal (more effort = better compression)
    try std.testing.expect(best.len <= fast.len);

    // Both should decompress to original
    const decompressed = try decompress(allocator, fast, original.len + 100);
    defer allocator.free(decompressed);
    try std.testing.expectEqualStrings(original, decompressed);
}
