const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.assets);

/// Asset metadata
pub const AssetInfo = struct {
    /// SHA-256 hash of the asset content
    hash: [32]u8,

    /// Asset file path within the archive
    path: []const u8,

    /// Asset size in bytes
    size: u64,

    /// Offset within the ZIP file (for direct access)
    zip_offset: u64,
};

/// Asset store - manages loading assets from Assets.zip
pub const AssetStore = struct {
    allocator: std.mem.Allocator,

    /// Path to Assets.zip
    archive_path: []const u8,

    /// Asset index (hash -> info)
    assets_by_hash: std.AutoHashMap([32]u8, AssetInfo),

    /// Asset index (path -> info)
    assets_by_path: std.StringHashMap(AssetInfo),

    /// File handle for the archive
    archive_file: ?std.fs.File,

    /// Whether the store is loaded
    loaded: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, archive_path: []const u8) !Self {
        return .{
            .allocator = allocator,
            .archive_path = try allocator.dupe(u8, archive_path),
            .assets_by_hash = std.AutoHashMap([32]u8, AssetInfo).init(allocator),
            .assets_by_path = std.StringHashMap(AssetInfo).init(allocator),
            .archive_file = null,
            .loaded = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.archive_file) |file| {
            file.close();
        }

        // Free asset info paths
        var iter = self.assets_by_path.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.assets_by_hash.deinit();
        self.assets_by_path.deinit();
        self.allocator.free(self.archive_path);
    }

    /// Load the asset archive and build index
    pub fn load(self: *Self) !void {
        log.info("Loading asset store from: {s}", .{self.archive_path});

        // Open the archive file
        self.archive_file = std.fs.openFileAbsolute(self.archive_path, .{}) catch |err| {
            log.err("Failed to open asset archive: {}", .{err});
            return err;
        };

        // Read ZIP central directory
        try self.readZipDirectory();

        self.loaded = true;
        log.info("Asset store loaded: {d} assets", .{self.assets_by_path.count()});
    }

    /// Read ZIP central directory to build asset index
    fn readZipDirectory(self: *Self) !void {
        const file = self.archive_file orelse return error.NotOpened;

        // Find End of Central Directory record
        // For simplicity, we scan from the end backwards
        const file_size = try file.getEndPos();

        if (file_size < 22) {
            return error.InvalidZip;
        }

        // Read last 64KB or file size, whichever is smaller
        const search_size: usize = @min(file_size, 65536);
        try file.seekTo(file_size - search_size);

        var search_buf = try self.allocator.alloc(u8, search_size);
        defer self.allocator.free(search_buf);

        const bytes_read = try file.readAll(search_buf);
        if (bytes_read < 22) {
            return error.InvalidZip;
        }

        // Look for EOCD signature (0x06054b50)
        var eocd_offset: ?usize = null;
        var i: usize = bytes_read - 22;
        while (i > 0) : (i -= 1) {
            if (search_buf[i] == 0x50 and
                search_buf[i + 1] == 0x4b and
                search_buf[i + 2] == 0x05 and
                search_buf[i + 3] == 0x06)
            {
                eocd_offset = i;
                break;
            }
        }

        if (eocd_offset == null) {
            return error.InvalidZip;
        }

        // Parse EOCD
        const eocd = search_buf[eocd_offset.?..];
        const cd_size = std.mem.readInt(u32, eocd[12..16], .little);
        const cd_offset = std.mem.readInt(u32, eocd[16..20], .little);
        const entry_count = std.mem.readInt(u16, eocd[10..12], .little);

        log.debug("ZIP: {d} entries, CD at offset {d}, size {d}", .{ entry_count, cd_offset, cd_size });

        // Read central directory
        try file.seekTo(cd_offset);

        var cd_buf = try self.allocator.alloc(u8, cd_size);
        defer self.allocator.free(cd_buf);

        _ = try file.readAll(cd_buf);

        // Parse central directory entries
        var offset: usize = 0;
        var count: usize = 0;

        while (offset + 46 <= cd_buf.len and count < entry_count) {
            // Check signature
            if (cd_buf[offset] != 0x50 or cd_buf[offset + 1] != 0x4b or
                cd_buf[offset + 2] != 0x01 or cd_buf[offset + 3] != 0x02)
            {
                break;
            }

            // Parse entry
            const uncompressed_size = std.mem.readInt(u32, cd_buf[offset + 24 ..][0..4], .little);
            const filename_len = std.mem.readInt(u16, cd_buf[offset + 28 ..][0..2], .little);
            const extra_len = std.mem.readInt(u16, cd_buf[offset + 30 ..][0..2], .little);
            const comment_len = std.mem.readInt(u16, cd_buf[offset + 32 ..][0..2], .little);
            const local_offset = std.mem.readInt(u32, cd_buf[offset + 42 ..][0..4], .little);

            // Read filename
            const filename_start = offset + 46;
            const filename_end = filename_start + filename_len;

            if (filename_end > cd_buf.len) {
                break;
            }

            const filename = cd_buf[filename_start..filename_end];

            // Skip directories
            if (filename.len > 0 and filename[filename.len - 1] != '/') {
                // Create asset info
                const path = try self.allocator.dupe(u8, filename);

                // Calculate hash (would need to read file content)
                var hash: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(path, &hash, .{});

                const info = AssetInfo{
                    .hash = hash,
                    .path = path,
                    .size = uncompressed_size,
                    .zip_offset = local_offset,
                };

                try self.assets_by_path.put(path, info);
                try self.assets_by_hash.put(hash, info);
            }

            offset = filename_end + extra_len + comment_len;
            count += 1;
        }

        log.debug("Indexed {d} assets", .{count});
    }

    /// Get asset by SHA-256 hash
    pub fn getByHash(self: *const Self, hash: [32]u8) ?AssetInfo {
        return self.assets_by_hash.get(hash);
    }

    /// Get asset by path
    pub fn getByPath(self: *const Self, path: []const u8) ?AssetInfo {
        return self.assets_by_path.get(path);
    }

    /// Read asset content by path
    pub fn readAsset(self: *Self, path: []const u8) ![]u8 {
        const info = self.getByPath(path) orelse return error.AssetNotFound;
        return self.readAssetByOffset(info.zip_offset, info.size);
    }

    /// Read asset content by hash
    pub fn readAssetByHash(self: *Self, hash: [32]u8) ![]u8 {
        const info = self.getByHash(hash) orelse return error.AssetNotFound;
        return self.readAssetByOffset(info.zip_offset, info.size);
    }

    /// Read asset content from ZIP by local file header offset
    fn readAssetByOffset(self: *Self, offset: u64, size: u64) ![]u8 {
        const file = self.archive_file orelse return error.NotOpened;

        // Seek to local file header
        try file.seekTo(offset);

        // Read local file header
        var header: [30]u8 = undefined;
        _ = try file.readAll(&header);

        // Verify signature
        if (header[0] != 0x50 or header[1] != 0x4b or
            header[2] != 0x03 or header[3] != 0x04)
        {
            return error.InvalidLocalHeader;
        }

        // Get filename and extra field lengths
        const filename_len = std.mem.readInt(u16, header[26..28], .little);
        const extra_len = std.mem.readInt(u16, header[28..30], .little);

        // Skip to data
        try file.seekBy(filename_len + extra_len);

        // Read data
        const data = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(data);

        _ = try file.readAll(data);

        return data;
    }

    /// Get total number of assets
    pub fn count(self: *const Self) usize {
        return self.assets_by_path.count();
    }

    /// Check if store is loaded
    pub fn isLoaded(self: *const Self) bool {
        return self.loaded;
    }
};

/// Asset streaming chunk size (4MB as per plan)
pub const ASSET_CHUNK_SIZE: usize = 4 * 1024 * 1024;

/// Represents an asset being streamed to a client
pub const AssetStream = struct {
    allocator: std.mem.Allocator,
    asset_id: u32,
    hash: [32]u8,
    data: []const u8,
    total_size: usize,
    bytes_sent: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, asset_id: u32, hash: [32]u8, data: []const u8) Self {
        return .{
            .allocator = allocator,
            .asset_id = asset_id,
            .hash = hash,
            .data = data,
            .total_size = data.len,
            .bytes_sent = 0,
        };
    }

    /// Get next chunk to send
    pub fn nextChunk(self: *Self) ?[]const u8 {
        if (self.bytes_sent >= self.total_size) {
            return null;
        }

        const remaining = self.total_size - self.bytes_sent;
        const chunk_size = @min(remaining, ASSET_CHUNK_SIZE);
        const chunk = self.data[self.bytes_sent .. self.bytes_sent + chunk_size];

        self.bytes_sent += chunk_size;

        return chunk;
    }

    /// Check if streaming is complete
    pub fn isComplete(self: *const Self) bool {
        return self.bytes_sent >= self.total_size;
    }

    /// Get progress percentage
    pub fn progress(self: *const Self) f32 {
        if (self.total_size == 0) return 100.0;
        return @as(f32, @floatFromInt(self.bytes_sent)) / @as(f32, @floatFromInt(self.total_size)) * 100.0;
    }
};

test "asset store init" {
    const allocator = std.testing.allocator;

    var store = try AssetStore.init(allocator, "test.zip");
    defer store.deinit();

    try std.testing.expect(!store.isLoaded());
    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "asset stream" {
    const allocator = std.testing.allocator;

    const data = "Hello, World!";
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});

    var stream = AssetStream.init(allocator, 1, hash, data);

    try std.testing.expect(!stream.isComplete());

    const chunk = stream.nextChunk();
    try std.testing.expect(chunk != null);
    try std.testing.expectEqualStrings(data, chunk.?);

    try std.testing.expect(stream.isComplete());
    try std.testing.expect(stream.nextChunk() == null);
}
