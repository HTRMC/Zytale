const std = @import("std");

const log = std.log.scoped(.assets);

/// Asset index entry from CommonAssetsIndex.hashes
pub const AssetIndexEntry = struct {
    /// Asset path (relative to assets root)
    path: []const u8,

    /// SHA-256 hash of asset content
    hash: [32]u8,

    /// Asset size in bytes
    size: u64,
};

/// Parser for CommonAssetsIndex.hashes file
/// Format (per line): <hex_hash> <size> <path>
pub const AssetIndex = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(AssetIndexEntry),
    by_hash: std.AutoHashMap([32]u8, usize),
    by_path: std.StringHashMap(usize),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(AssetIndexEntry).init(allocator),
            .by_hash = std.AutoHashMap([32]u8, usize).init(allocator),
            .by_path = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.path);
        }
        self.entries.deinit();
        self.by_hash.deinit();
        self.by_path.deinit();
    }

    /// Load index from file
    pub fn loadFromFile(self: *Self, path: []const u8) !void {
        log.info("Loading asset index from: {s}", .{path});

        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 100); // 100MB max
        defer self.allocator.free(content);

        try self.parse(content);

        log.info("Loaded {d} asset entries", .{self.entries.items.len});
    }

    /// Parse index content
    pub fn parse(self: *Self, content: []const u8) !void {
        var lines = std.mem.splitSequence(u8, content, "\n");

        while (lines.next()) |line| {
            // Skip empty lines and comments
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            try self.parseLine(trimmed);
        }
    }

    /// Parse a single line: <hash> <size> <path>
    fn parseLine(self: *Self, line: []const u8) !void {
        // Find first space (after hash)
        const hash_end = std.mem.indexOf(u8, line, " ") orelse return error.InvalidFormat;
        const hash_str = line[0..hash_end];

        if (hash_str.len != 64) {
            return error.InvalidHash;
        }

        // Find second space (after size)
        const rest = line[hash_end + 1 ..];
        const size_end = std.mem.indexOf(u8, rest, " ") orelse return error.InvalidFormat;
        const size_str = rest[0..size_end];

        // Path is everything after
        const path = rest[size_end + 1 ..];

        if (path.len == 0) {
            return error.InvalidFormat;
        }

        // Parse hash
        var hash: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&hash, hash_str) catch return error.InvalidHash;

        // Parse size
        const size = std.fmt.parseInt(u64, size_str, 10) catch return error.InvalidSize;

        // Store entry
        const path_copy = try self.allocator.dupe(u8, path);

        const idx = self.entries.items.len;
        try self.entries.append(.{
            .path = path_copy,
            .hash = hash,
            .size = size,
        });

        try self.by_hash.put(hash, idx);
        try self.by_path.put(path_copy, idx);
    }

    /// Get entry by hash
    pub fn getByHash(self: *const Self, hash: [32]u8) ?*const AssetIndexEntry {
        const idx = self.by_hash.get(hash) orelse return null;
        return &self.entries.items[idx];
    }

    /// Get entry by path
    pub fn getByPath(self: *const Self, path: []const u8) ?*const AssetIndexEntry {
        const idx = self.by_path.get(path) orelse return null;
        return &self.entries.items[idx];
    }

    /// Get total count
    pub fn count(self: *const Self) usize {
        return self.entries.items.len;
    }

    /// Get all hashes (for RequestAssets response)
    pub fn getAllHashes(self: *const Self, allocator: std.mem.Allocator) ![][32]u8 {
        const hashes = try allocator.alloc([32]u8, self.entries.items.len);
        for (self.entries.items, 0..) |entry, i| {
            hashes[i] = entry.hash;
        }
        return hashes;
    }
};

/// Parse a hex string into bytes
pub fn parseHex(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) {
        return error.InvalidLength;
    }

    for (0..out.len) |i| {
        const high = charToNibble(hex[i * 2]) orelse return error.InvalidHex;
        const low = charToNibble(hex[i * 2 + 1]) orelse return error.InvalidHex;
        out[i] = (high << 4) | low;
    }
}

fn charToNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

/// Format hash as hex string
pub fn hashToHex(hash: [32]u8) [64]u8 {
    const chars = "0123456789abcdef";
    var result: [64]u8 = undefined;

    for (hash, 0..) |byte, i| {
        result[i * 2] = chars[byte >> 4];
        result[i * 2 + 1] = chars[byte & 0x0F];
    }

    return result;
}

test "asset index parsing" {
    const allocator = std.testing.allocator;

    var index = AssetIndex.init(allocator);
    defer index.deinit();

    const test_content =
        \\0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef 1234 path/to/file.txt
        \\fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210 5678 another/file.bin
    ;

    try index.parse(test_content);

    try std.testing.expectEqual(@as(usize, 2), index.count());

    // Check first entry
    const entry1 = index.getByPath("path/to/file.txt");
    try std.testing.expect(entry1 != null);
    try std.testing.expectEqual(@as(u64, 1234), entry1.?.size);

    // Check second entry
    const entry2 = index.getByPath("another/file.bin");
    try std.testing.expect(entry2 != null);
    try std.testing.expectEqual(@as(u64, 5678), entry2.?.size);
}

test "hash conversion" {
    const hash = [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF } ++ [_]u8{0} ** 24;
    const hex = hashToHex(hash);
    try std.testing.expectEqualStrings("0123456789abcdef000000000000000000000000000000000000000000000000", &hex);
}
