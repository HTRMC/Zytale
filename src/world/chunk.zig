const std = @import("std");
const constants = @import("constants.zig");
const Section = @import("section.zig").Section;

/// A full chunk column containing HEIGHT_SECTIONS vertical sections
/// Each chunk is 32x320x32 blocks (32 wide, 320 tall, 32 deep)
pub const Chunk = struct {
    allocator: std.mem.Allocator,

    /// Chunk coordinates
    x: i32,
    z: i32,

    /// Vertical sections (Y=0-31, Y=32-63, ... Y=288-319)
    sections: [constants.HEIGHT_SECTIONS]*Section,

    /// Heightmap - highest solid block Y for each X,Z
    heightmap: [constants.HEIGHTMAP_SIZE]i16,

    /// Tintmap - ARGB color for grass tint at each X,Z
    tintmap: [constants.TINTMAP_SIZE]u32,

    /// Environment map (biome-like data)
    environments: [constants.TINTMAP_SIZE]u8,

    /// Track if chunk is dirty (modified)
    dirty: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, x: i32, z: i32) !Self {
        var sections: [constants.HEIGHT_SECTIONS]*Section = undefined;

        for (0..constants.HEIGHT_SECTIONS) |i| {
            const section = try allocator.create(Section);
            section.* = Section.init(allocator);
            sections[i] = section;
        }

        return .{
            .allocator = allocator,
            .x = x,
            .z = z,
            .sections = sections,
            .heightmap = [_]i16{0} ** constants.HEIGHTMAP_SIZE,
            .tintmap = [_]u32{constants.DEFAULT_GRASS_TINT} ** constants.TINTMAP_SIZE,
            .environments = [_]u8{0} ** constants.TINTMAP_SIZE,
            .dirty = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.sections) |section| {
            section.deinit();
            self.allocator.destroy(section);
        }
    }

    /// Get block at world coordinates within this chunk
    pub fn getBlock(self: *const Self, x: i32, y: i32, z: i32) u16 {
        if (y < constants.MIN_Y or y >= constants.MAX_Y) {
            return constants.BlockId.AIR;
        }

        const section_idx = constants.indexSection(y);
        const local_y = @mod(y, @as(i32, constants.SECTION_SIZE));
        const local_x = @mod(x, @as(i32, constants.SECTION_SIZE));
        const local_z = @mod(z, @as(i32, constants.SECTION_SIZE));

        return self.sections[section_idx].getBlock(
            @intCast(local_x),
            @intCast(local_y),
            @intCast(local_z),
        );
    }

    /// Set block at world coordinates within this chunk
    pub fn setBlock(self: *Self, x: i32, y: i32, z: i32, block_id: u16) !void {
        if (y < constants.MIN_Y or y >= constants.MAX_Y) {
            return;
        }

        const section_idx = constants.indexSection(y);
        const local_y: u32 = @intCast(@mod(y, @as(i32, constants.SECTION_SIZE)));
        const local_x: u32 = @intCast(@mod(x, @as(i32, constants.SECTION_SIZE)));
        const local_z: u32 = @intCast(@mod(z, @as(i32, constants.SECTION_SIZE)));

        try self.sections[section_idx].setBlock(local_x, local_y, local_z, block_id);
        self.dirty = true;

        // Update heightmap
        self.updateHeightmap(local_x, y, local_z, block_id);
    }

    /// Fill a Y range with a block
    pub fn fillYRange(self: *Self, y_min: i32, y_max: i32, block_id: u16) !void {
        const start: usize = @intCast(@max(0, y_min));
        const end: usize = @intCast(@min(constants.MAX_Y, y_max));
        for (start..end) |y| {
            const section_idx = constants.indexSection(@intCast(y));
            const local_y: u32 = @intCast(@mod(@as(i32, @intCast(y)), @as(i32, constants.SECTION_SIZE)));

            try self.sections[section_idx].fillLayer(local_y, block_id);
        }

        self.dirty = true;
    }

    /// Update heightmap for a position
    fn updateHeightmap(self: *Self, x: u32, y: i32, z: u32, block_id: u16) void {
        const idx = z * constants.SECTION_SIZE + x;

        if (block_id != constants.BlockId.AIR) {
            // Block placed - update if higher than current
            if (y > self.heightmap[idx]) {
                self.heightmap[idx] = @intCast(y);
            }
        } else {
            // Air placed - might need to find new highest block
            if (y >= self.heightmap[idx]) {
                self.recalculateHeightmapColumn(x, z);
            }
        }
    }

    /// Recalculate heightmap for a single column
    fn recalculateHeightmapColumn(self: *Self, x: u32, z: u32) void {
        const idx = z * constants.SECTION_SIZE + x;
        self.heightmap[idx] = 0;

        var y: i32 = constants.MAX_Y - 1;
        while (y >= 0) : (y -= 1) {
            if (self.getBlock(@intCast(x), y, @intCast(z)) != constants.BlockId.AIR) {
                self.heightmap[idx] = @intCast(y);
                break;
            }
        }
    }

    /// Recalculate entire heightmap
    pub fn recalculateHeightmap(self: *Self) void {
        for (0..constants.SECTION_SIZE) |z| {
            for (0..constants.SECTION_SIZE) |x| {
                self.recalculateHeightmapColumn(@intCast(x), @intCast(z));
            }
        }
    }

    /// Set tint color for a position
    pub fn setTint(self: *Self, x: u32, z: u32, argb: u32) void {
        const idx = z * constants.SECTION_SIZE + x;
        self.tintmap[idx] = argb;
    }

    /// Fill entire tintmap with a color
    pub fn fillTintmap(self: *Self, argb: u32) void {
        @memset(&self.tintmap, argb);
    }

    /// Get section at index
    pub fn getSection(self: *Self, idx: u32) *Section {
        return self.sections[idx];
    }

    /// Serialize heightmap for network transmission
    /// Format: raw i16 array (little-endian)
    pub fn serializeHeightmap(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, constants.HEIGHTMAP_BYTES);

        for (0..constants.HEIGHTMAP_SIZE) |i| {
            const offset = i * 2;
            std.mem.writeInt(i16, buf[offset..][0..2], self.heightmap[i], .little);
        }

        return buf;
    }

    /// Serialize tintmap for network transmission
    /// Format: raw u32 array (little-endian ARGB)
    pub fn serializeTintmap(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, constants.TINTMAP_BYTES);

        for (0..constants.TINTMAP_SIZE) |i| {
            const offset = i * 4;
            std.mem.writeInt(u32, buf[offset..][0..4], self.tintmap[i], .little);
        }

        return buf;
    }

    /// Serialize environments map for network transmission
    /// Format: raw u8 array
    pub fn serializeEnvironments(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, constants.TINTMAP_SIZE);
        @memcpy(buf, &self.environments);
        return buf;
    }
};

test "chunk basic operations" {
    const allocator = std.testing.allocator;

    var chunk = try Chunk.init(allocator, 0, 0);
    defer chunk.deinit();

    // Initially all air
    try std.testing.expectEqual(constants.BlockId.AIR, chunk.getBlock(0, 0, 0));
    try std.testing.expectEqual(constants.BlockId.AIR, chunk.getBlock(0, 319, 0));

    // Set a block
    try chunk.setBlock(5, 100, 15, constants.BlockId.STONE);
    try std.testing.expectEqual(constants.BlockId.STONE, chunk.getBlock(5, 100, 15));

    // Heightmap should be updated
    const idx: u32 = 15 * constants.SECTION_SIZE + 5;
    try std.testing.expectEqual(@as(i16, 100), chunk.heightmap[idx]);
}

test "chunk fill y range" {
    const allocator = std.testing.allocator;

    var chunk = try Chunk.init(allocator, 0, 0);
    defer chunk.deinit();

    // Fill Y=0-64 with stone
    try chunk.fillYRange(0, 64, constants.BlockId.STONE);

    try std.testing.expectEqual(constants.BlockId.STONE, chunk.getBlock(0, 0, 0));
    try std.testing.expectEqual(constants.BlockId.STONE, chunk.getBlock(0, 63, 0));
    try std.testing.expectEqual(constants.BlockId.AIR, chunk.getBlock(0, 64, 0));
}

test "chunk serialization" {
    const allocator = std.testing.allocator;

    var chunk = try Chunk.init(allocator, 0, 0);
    defer chunk.deinit();

    // Set some heightmap values
    chunk.heightmap[0] = 100;
    chunk.heightmap[100] = 200;

    // Serialize heightmap
    const heightmap_data = try chunk.serializeHeightmap(allocator);
    defer allocator.free(heightmap_data);

    try std.testing.expectEqual(@as(usize, constants.HEIGHTMAP_BYTES), heightmap_data.len);
    try std.testing.expectEqual(@as(i16, 100), std.mem.readInt(i16, heightmap_data[0..2], .little));
    try std.testing.expectEqual(@as(i16, 200), std.mem.readInt(i16, heightmap_data[200..202], .little));

    // Serialize tintmap
    const tintmap_data = try chunk.serializeTintmap(allocator);
    defer allocator.free(tintmap_data);

    try std.testing.expectEqual(@as(usize, constants.TINTMAP_BYTES), tintmap_data.len);
}
