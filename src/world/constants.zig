/// Hytale World Constants
/// Based on ChunkUtil.java and BlockSection.java

/// Size of a chunk section in blocks (per axis)
pub const SECTION_SIZE: u32 = 32;

/// Total blocks per section (32x32x32)
pub const SECTION_BLOCK_COUNT: u32 = SECTION_SIZE * SECTION_SIZE * SECTION_SIZE; // 32768

/// Number of vertical sections in a chunk column
pub const HEIGHT_SECTIONS: u32 = 10;

/// Total world height in blocks (10 sections * 32 blocks)
pub const WORLD_HEIGHT: u32 = SECTION_SIZE * HEIGHT_SECTIONS; // 320

/// Minimum Y coordinate
pub const MIN_Y: i32 = 0;

/// Maximum Y coordinate (exclusive)
pub const MAX_Y: i32 = @intCast(WORLD_HEIGHT);

/// Spawn height for flat world (Y=81)
pub const FLAT_SPAWN_Y: i32 = 81;

/// Bits needed for section X/Z coordinate within block index
pub const SECTION_COORD_BITS: u5 = 5; // log2(32) = 5

/// Mask for section coordinate (0-31)
pub const SECTION_COORD_MASK: u32 = SECTION_SIZE - 1; // 0x1F

/// Heightmap entry count per chunk (32x32)
pub const HEIGHTMAP_SIZE: u32 = SECTION_SIZE * SECTION_SIZE; // 1024

/// Heightmap data size in bytes (1024 * 2 bytes per i16)
pub const HEIGHTMAP_BYTES: u32 = HEIGHTMAP_SIZE * 2; // 2048

/// Tintmap entry count per chunk (32x32)
pub const TINTMAP_SIZE: u32 = SECTION_SIZE * SECTION_SIZE; // 1024

/// Tintmap data size in bytes (1024 * 4 bytes per ARGB)
pub const TINTMAP_BYTES: u32 = TINTMAP_SIZE * 4; // 4096

/// Block IDs for flat world generation
pub const BlockId = struct {
    pub const AIR: u16 = 0;
    pub const BEDROCK: u16 = 1;
    pub const STONE: u16 = 2;
    pub const DIRT: u16 = 3;
    pub const GRASS: u16 = 4;
};

/// Flat world layer heights
pub const FlatWorldLayers = struct {
    /// Bedrock layer (Y=0 to Y=1)
    pub const BEDROCK_MIN: i32 = 0;
    pub const BEDROCK_MAX: i32 = 1;

    /// Stone layer (Y=1 to Y=60)
    pub const STONE_MIN: i32 = 1;
    pub const STONE_MAX: i32 = 60;

    /// Dirt layer (Y=60 to Y=63)
    pub const DIRT_MIN: i32 = 60;
    pub const DIRT_MAX: i32 = 63;

    /// Grass layer (Y=63 to Y=64)
    pub const GRASS_MIN: i32 = 63;
    pub const GRASS_MAX: i32 = 64;

    /// Surface height (top of grass)
    pub const SURFACE_Y: i32 = 64;
};

/// Calculate block index within a section from local coordinates
/// Formula: ((y & 31) << 10) | ((z & 31) << 5) | (x & 31)
pub fn indexBlock(x: i32, y: i32, z: i32) u32 {
    const local_x: u32 = @intCast(x & SECTION_COORD_MASK);
    const local_y: u32 = @intCast(y & SECTION_COORD_MASK);
    const local_z: u32 = @intCast(z & SECTION_COORD_MASK);
    return (local_y << 10) | (local_z << 5) | local_x;
}

/// Calculate section index from Y coordinate
/// Formula: y >> 5 (y / 32)
pub fn indexSection(y: i32) u32 {
    if (y < 0) return 0;
    if (y >= MAX_Y) return HEIGHT_SECTIONS - 1;
    return @intCast(@as(u32, @intCast(y)) >> SECTION_COORD_BITS);
}

/// Get Y coordinate from section index
pub fn sectionToY(section: u32) i32 {
    return @intCast(section * SECTION_SIZE);
}

/// Convert world coordinates to chunk coordinates
pub fn worldToChunk(x: i32, z: i32) struct { cx: i32, cz: i32 } {
    return .{
        .cx = @divFloor(x, @as(i32, SECTION_SIZE)),
        .cz = @divFloor(z, @as(i32, SECTION_SIZE)),
    };
}

/// Convert world coordinates to local coordinates within chunk
pub fn worldToLocal(x: i32, y: i32, z: i32) struct { lx: u32, ly: u32, lz: u32 } {
    return .{
        .lx = @intCast(@mod(x, @as(i32, SECTION_SIZE))),
        .ly = @intCast(@mod(y, @as(i32, SECTION_SIZE))),
        .lz = @intCast(@mod(z, @as(i32, SECTION_SIZE))),
    };
}

/// Default grass tint ARGB (from FlatWorldGenProvider.java: Color(91, -98, 40))
/// Java Color constructor with signed bytes: 91, -98 (158), 40
pub const DEFAULT_GRASS_TINT: u32 = 0xFF5B9E28; // ARGB: 255, 91, 158, 40

// Tests
test "index calculations" {
    const std = @import("std");

    // Test block index
    try std.testing.expectEqual(@as(u32, 0), indexBlock(0, 0, 0));
    try std.testing.expectEqual(@as(u32, 1), indexBlock(1, 0, 0));
    try std.testing.expectEqual(@as(u32, 32), indexBlock(0, 0, 1));
    try std.testing.expectEqual(@as(u32, 1024), indexBlock(0, 1, 0));

    // Test section index
    try std.testing.expectEqual(@as(u32, 0), indexSection(0));
    try std.testing.expectEqual(@as(u32, 0), indexSection(31));
    try std.testing.expectEqual(@as(u32, 1), indexSection(32));
    try std.testing.expectEqual(@as(u32, 1), indexSection(63));
    try std.testing.expectEqual(@as(u32, 2), indexSection(64));
    try std.testing.expectEqual(@as(u32, 9), indexSection(319));
}

test "world to chunk conversion" {
    const std = @import("std");

    const pos1 = worldToChunk(0, 0);
    try std.testing.expectEqual(@as(i32, 0), pos1.cx);
    try std.testing.expectEqual(@as(i32, 0), pos1.cz);

    const pos2 = worldToChunk(31, 31);
    try std.testing.expectEqual(@as(i32, 0), pos2.cx);
    try std.testing.expectEqual(@as(i32, 0), pos2.cz);

    const pos3 = worldToChunk(32, 32);
    try std.testing.expectEqual(@as(i32, 1), pos3.cx);
    try std.testing.expectEqual(@as(i32, 1), pos3.cz);

    const pos4 = worldToChunk(-1, -1);
    try std.testing.expectEqual(@as(i32, -1), pos4.cx);
    try std.testing.expectEqual(@as(i32, -1), pos4.cz);
}
