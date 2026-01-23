const std = @import("std");
const constants = @import("constants.zig");
const Chunk = @import("chunk.zig").Chunk;
const Section = @import("section.zig").Section;

const BlockId = constants.BlockId;
const FlatWorldLayers = constants.FlatWorldLayers;

/// Flat world generator
/// Generates a simple flat world with bedrock, stone, dirt, and grass layers
/// Based on FlatWorldGenProvider.java
pub const FlatWorldGenerator = struct {
    allocator: std.mem.Allocator,

    /// Default grass tint color
    tint_color: u32,

    /// Spawn point
    spawn_x: i32,
    spawn_y: i32,
    spawn_z: i32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .tint_color = constants.DEFAULT_GRASS_TINT,
            .spawn_x = 0,
            .spawn_y = constants.FLAT_SPAWN_Y,
            .spawn_z = 0,
        };
    }

    /// Generate a flat chunk at the given coordinates
    pub fn generateChunk(self: *Self, x: i32, z: i32) !*Chunk {
        const chunk = try self.allocator.create(Chunk);
        chunk.* = try Chunk.init(self.allocator, x, z);
        errdefer {
            chunk.deinit();
            self.allocator.destroy(chunk);
        }

        // Generate flat terrain layers
        try self.generateLayers(chunk);

        // Set tintmap to default grass color
        chunk.fillTintmap(self.tint_color);

        // Recalculate heightmap
        chunk.recalculateHeightmap();

        return chunk;
    }

    /// Generate terrain layers for a chunk
    fn generateLayers(self: *Self, chunk: *Chunk) !void {
        _ = self;

        // Bedrock layer (Y=0)
        try chunk.fillYRange(FlatWorldLayers.BEDROCK_MIN, FlatWorldLayers.BEDROCK_MAX, BlockId.BEDROCK);

        // Stone layer (Y=1-59)
        try chunk.fillYRange(FlatWorldLayers.STONE_MIN, FlatWorldLayers.STONE_MAX, BlockId.STONE);

        // Dirt layer (Y=60-62)
        try chunk.fillYRange(FlatWorldLayers.DIRT_MIN, FlatWorldLayers.DIRT_MAX, BlockId.DIRT);

        // Grass layer (Y=63)
        try chunk.fillYRange(FlatWorldLayers.GRASS_MIN, FlatWorldLayers.GRASS_MAX, BlockId.GRASS);

        // Everything above is air (default)
    }

    /// Generate a single section at given chunk coordinates and section index
    /// Useful for sending individual sections via SetChunk packet
    pub fn generateSection(self: *Self, _: i32, section_y: u32, _: i32) !*Section {
        const section = try self.allocator.create(Section);
        section.* = Section.init(self.allocator);
        errdefer {
            section.deinit();
            self.allocator.destroy(section);
        }

        // Calculate Y range for this section
        const y_base = constants.sectionToY(section_y);
        const y_end = y_base + @as(i32, constants.SECTION_SIZE);

        // Section 0 (Y=0-31): bedrock at 0, stone 1-31
        // Section 1 (Y=32-63): stone 32-59, dirt 60-62, grass 63
        // Sections 2-9 (Y=64+): all air

        for (0..constants.SECTION_SIZE) |local_y| {
            const world_y = y_base + @as(i32, @intCast(local_y));

            const block_id: u16 = if (world_y < FlatWorldLayers.BEDROCK_MAX)
                BlockId.BEDROCK
            else if (world_y < FlatWorldLayers.STONE_MAX)
                BlockId.STONE
            else if (world_y < FlatWorldLayers.DIRT_MAX)
                BlockId.DIRT
            else if (world_y < FlatWorldLayers.GRASS_MAX)
                BlockId.GRASS
            else
                BlockId.AIR;

            if (block_id != BlockId.AIR) {
                try section.fillLayer(@intCast(local_y), block_id);
            }
        }

        // Check if section ends up empty (all air)
        _ = y_end;

        return section;
    }

    /// Check if a section at given Y index would be empty (all air)
    pub fn isSectionEmpty(section_y: u32) bool {
        const y_base = constants.sectionToY(section_y);
        // Any section starting at or above grass layer is empty
        return y_base >= FlatWorldLayers.GRASS_MAX;
    }

    /// Get spawn point
    pub fn getSpawnPoint(self: *const Self) struct { x: i32, y: i32, z: i32 } {
        return .{
            .x = self.spawn_x,
            .y = self.spawn_y,
            .z = self.spawn_z,
        };
    }
};

test "flat world generation" {
    const allocator = std.testing.allocator;

    var gen = FlatWorldGenerator.init(allocator);

    const chunk = try gen.generateChunk(0, 0);
    defer {
        chunk.deinit();
        allocator.destroy(chunk);
    }

    // Check layer structure
    try std.testing.expectEqual(BlockId.BEDROCK, chunk.getBlock(0, 0, 0));
    try std.testing.expectEqual(BlockId.STONE, chunk.getBlock(0, 1, 0));
    try std.testing.expectEqual(BlockId.STONE, chunk.getBlock(0, 59, 0));
    try std.testing.expectEqual(BlockId.DIRT, chunk.getBlock(0, 60, 0));
    try std.testing.expectEqual(BlockId.DIRT, chunk.getBlock(0, 62, 0));
    try std.testing.expectEqual(BlockId.GRASS, chunk.getBlock(0, 63, 0));
    try std.testing.expectEqual(BlockId.AIR, chunk.getBlock(0, 64, 0));

    // Check heightmap
    try std.testing.expectEqual(@as(i16, 63), chunk.heightmap[0]);
}

test "flat world section generation" {
    const allocator = std.testing.allocator;

    var gen = FlatWorldGenerator.init(allocator);

    // Section 0 should have bedrock and stone
    const section0 = try gen.generateSection(0, 0, 0);
    defer {
        section0.deinit();
        allocator.destroy(section0);
    }

    try std.testing.expectEqual(BlockId.BEDROCK, section0.getBlock(0, 0, 0));
    try std.testing.expectEqual(BlockId.STONE, section0.getBlock(0, 31, 0));

    // Section 1 should have stone, dirt, grass
    const section1 = try gen.generateSection(0, 1, 0);
    defer {
        section1.deinit();
        allocator.destroy(section1);
    }

    // Y=60 in world = local Y=28 in section 1
    try std.testing.expectEqual(BlockId.DIRT, section1.getBlock(0, 28, 0)); // Y=60
    try std.testing.expectEqual(BlockId.GRASS, section1.getBlock(0, 31, 0)); // Y=63

    // Section 2+ should be empty
    try std.testing.expect(FlatWorldGenerator.isSectionEmpty(2));
    try std.testing.expect(FlatWorldGenerator.isSectionEmpty(9));
    try std.testing.expect(!FlatWorldGenerator.isSectionEmpty(0));
    try std.testing.expect(!FlatWorldGenerator.isSectionEmpty(1));
}
