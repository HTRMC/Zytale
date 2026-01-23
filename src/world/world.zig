const std = @import("std");
const constants = @import("constants.zig");
const Chunk = @import("chunk.zig").Chunk;
const Section = @import("section.zig").Section;
const FlatWorldGenerator = @import("flatworld.zig").FlatWorldGenerator;

/// Spawn point coordinates
pub const SpawnPoint = struct { x: i32, y: i32, z: i32 };

/// World UUID type
pub const WorldUuid = [16]u8;

/// Generate a random world UUID
pub fn generateWorldUuid() WorldUuid {
    var uuid: WorldUuid = undefined;
    const io = std.Io.Threaded.global_single_threaded.io();
    io.random(&uuid);

    // Set version (4) and variant (2) bits per RFC 4122
    uuid[6] = (uuid[6] & 0x0F) | 0x40; // Version 4
    uuid[8] = (uuid[8] & 0x3F) | 0x80; // Variant 2

    return uuid;
}

/// World manager - handles chunk storage and generation
pub const World = struct {
    allocator: std.mem.Allocator,

    /// World UUID (unique identifier)
    uuid: WorldUuid,

    /// Loaded chunks (keyed by packed X,Z coordinates)
    chunks: std.AutoHashMap(i64, *Chunk),

    /// World generator
    generator: FlatWorldGenerator,

    /// World name
    name: []const u8,

    const Self = @This();

    /// Pack chunk coordinates into a single key
    fn packCoords(x: i32, z: i32) i64 {
        return (@as(i64, x) << 32) | @as(i64, @as(u32, @bitCast(z)));
    }

    /// Unpack coordinates from key
    fn unpackCoords(key: i64) struct { x: i32, z: i32 } {
        return .{
            .x = @intCast(key >> 32),
            .z = @bitCast(@as(u32, @truncate(@as(u64, @bitCast(key))))),
        };
    }

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Self {
        const name_copy = try allocator.dupe(u8, name);

        return .{
            .allocator = allocator,
            .uuid = generateWorldUuid(),
            .chunks = std.AutoHashMap(i64, *Chunk).init(allocator),
            .generator = FlatWorldGenerator.init(allocator),
            .name = name_copy,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all chunks
        var iter = self.chunks.valueIterator();
        while (iter.next()) |chunk_ptr| {
            chunk_ptr.*.deinit();
            self.allocator.destroy(chunk_ptr.*);
        }
        self.chunks.deinit();

        self.allocator.free(self.name);
    }

    /// Get or generate a chunk at coordinates
    pub fn getChunk(self: *Self, x: i32, z: i32) !*Chunk {
        const key = packCoords(x, z);

        // Check if already loaded
        if (self.chunks.get(key)) |chunk| {
            return chunk;
        }

        // Generate new chunk
        const chunk = try self.generator.generateChunk(x, z);
        try self.chunks.put(key, chunk);

        return chunk;
    }

    /// Get chunk if loaded, null otherwise
    pub fn getChunkIfLoaded(self: *Self, x: i32, z: i32) ?*Chunk {
        const key = packCoords(x, z);
        return self.chunks.get(key);
    }

    /// Unload a chunk
    pub fn unloadChunk(self: *Self, x: i32, z: i32) void {
        const key = packCoords(x, z);
        if (self.chunks.fetchRemove(key)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }

    /// Get block at world coordinates
    pub fn getBlock(self: *Self, x: i32, y: i32, z: i32) !u16 {
        const coords = constants.worldToChunk(x, z);
        const chunk = try self.getChunk(coords.cx, coords.cz);
        return chunk.getBlock(x, y, z);
    }

    /// Set block at world coordinates
    pub fn setBlock(self: *Self, x: i32, y: i32, z: i32, block_id: u16) !void {
        const coords = constants.worldToChunk(x, z);
        const chunk = try self.getChunk(coords.cx, coords.cz);
        try chunk.setBlock(x, y, z, block_id);
    }

    /// Get spawn point
    pub fn getSpawnPoint(self: *const Self) SpawnPoint {
        const sp = self.generator.getSpawnPoint();
        return .{ .x = sp.x, .y = sp.y, .z = sp.z };
    }

    /// Get all chunks within radius of a point
    pub fn getChunksInRadius(self: *Self, center_x: i32, center_z: i32, radius: u32) !std.ArrayList(*Chunk) {
        const center = constants.worldToChunk(center_x, center_z);
        var chunks: std.ArrayList(*Chunk) = .empty;

        const r: i32 = @intCast(radius);
        var cz: i32 = center.cz - r;
        while (cz <= center.cz + r) : (cz += 1) {
            var cx: i32 = center.cx - r;
            while (cx <= center.cx + r) : (cx += 1) {
                const chunk = try self.getChunk(cx, cz);
                try chunks.append(self.allocator, chunk);
            }
        }

        return chunks;
    }

    /// Get number of loaded chunks
    pub fn loadedChunkCount(self: *const Self) usize {
        return self.chunks.count();
    }
};

/// Convert UUID bytes to string format
pub fn uuidToString(uuid: WorldUuid) [36]u8 {
    const hex = "0123456789abcdef";
    var result: [36]u8 = undefined;
    var idx: usize = 0;

    for (0..16) |i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            result[idx] = '-';
            idx += 1;
        }
        result[idx] = hex[uuid[i] >> 4];
        idx += 1;
        result[idx] = hex[uuid[i] & 0x0F];
        idx += 1;
    }

    return result;
}

test "world basic operations" {
    const allocator = std.testing.allocator;

    var world = try World.init(allocator, "Test World");
    defer world.deinit();

    // Get chunk (should generate)
    const chunk = try world.getChunk(0, 0);
    try std.testing.expectEqual(@as(i32, 0), chunk.x);
    try std.testing.expectEqual(@as(i32, 0), chunk.z);

    // Chunk should now be loaded
    try std.testing.expectEqual(@as(usize, 1), world.loadedChunkCount());

    // Get same chunk again (should return cached)
    const chunk2 = try world.getChunk(0, 0);
    try std.testing.expectEqual(chunk, chunk2);

    // Get block
    const block = try world.getBlock(0, 0, 0);
    try std.testing.expectEqual(constants.BlockId.BEDROCK, block);
}

test "world chunk radius" {
    const allocator = std.testing.allocator;

    var world = try World.init(allocator, "Test World");
    defer world.deinit();

    // Get chunks in radius 1 around origin
    var chunks = try world.getChunksInRadius(0, 0, 1);
    defer chunks.deinit();

    // Should be 9 chunks (3x3)
    try std.testing.expectEqual(@as(usize, 9), chunks.items.len);
}

test "uuid generation" {
    const uuid1 = generateWorldUuid();
    const uuid2 = generateWorldUuid();

    // UUIDs should be different
    try std.testing.expect(!std.mem.eql(u8, &uuid1, &uuid2));

    // Check version byte
    try std.testing.expectEqual(@as(u8, 0x40), uuid1[6] & 0xF0);
    try std.testing.expectEqual(@as(u8, 0x80), uuid1[8] & 0xC0);
}
