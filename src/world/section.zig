const std = @import("std");
const constants = @import("constants.zig");
const palette = @import("palette.zig");
const varint = @import("../net/packet/varint.zig");

const PaletteType = palette.PaletteType;
const BlockPalette = palette.BlockPalette;
const PaletteData = palette.PaletteData;

/// A 32x32x32 block section
/// Based on BlockSection.java serialization format
pub const Section = struct {
    allocator: std.mem.Allocator,

    /// Block palette (maps indices to block IDs)
    block_palette: BlockPalette,

    /// Block data (palette indices)
    block_data: PaletteData,

    /// Filler palette (for block states like rotation)
    filler_palette: BlockPalette,
    filler_data: PaletteData,

    /// Rotation palette
    rotation_palette: BlockPalette,
    rotation_data: PaletteData,

    /// Track if section is dirty (modified)
    dirty: bool,

    /// Track if section is empty (all air)
    is_empty: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .block_palette = BlockPalette.init(allocator),
            .block_data = PaletteData.initEmpty(allocator),
            .filler_palette = BlockPalette.init(allocator),
            .filler_data = PaletteData.initEmpty(allocator),
            .rotation_palette = BlockPalette.init(allocator),
            .rotation_data = PaletteData.initEmpty(allocator),
            .dirty = false,
            .is_empty = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.block_palette.deinit();
        self.block_data.deinit();
        self.filler_palette.deinit();
        self.filler_data.deinit();
        self.rotation_palette.deinit();
        self.rotation_data.deinit();
    }

    /// Get block at local coordinates (0-31 for each axis)
    pub fn getBlock(self: *const Self, x: u32, y: u32, z: u32) u16 {
        if (self.is_empty) return constants.BlockId.AIR;

        const idx = constants.indexBlock(@intCast(x), @intCast(y), @intCast(z));
        const palette_idx = self.block_data.get(idx);
        return self.block_palette.get(palette_idx);
    }

    /// Set block at local coordinates
    pub fn setBlock(self: *Self, x: u32, y: u32, z: u32, block_id: u16) !void {
        const idx = constants.indexBlock(@intCast(x), @intCast(y), @intCast(z));

        // Add block to palette
        const palette_idx = try self.block_palette.add(block_id);

        // Ensure data storage matches palette type
        try self.ensureDataCapacity();

        // Set the value
        self.block_data.set(idx, palette_idx);

        self.dirty = true;
        self.is_empty = false;
    }

    /// Fill entire section with a single block
    pub fn fill(self: *Self, block_id: u16) !void {
        self.block_palette.clear();
        const palette_idx = try self.block_palette.add(block_id);

        try self.ensureDataCapacity();
        self.block_data.fill(palette_idx);

        self.dirty = true;
        self.is_empty = (block_id == constants.BlockId.AIR);
    }

    /// Fill a Y layer with a block
    pub fn fillLayer(self: *Self, y: u32, block_id: u16) !void {
        const palette_idx = try self.block_palette.add(block_id);
        try self.ensureDataCapacity();

        for (0..constants.SECTION_SIZE) |z| {
            for (0..constants.SECTION_SIZE) |x| {
                const idx = constants.indexBlock(@intCast(x), @intCast(y), @intCast(z));
                self.block_data.set(idx, palette_idx);
            }
        }

        self.dirty = true;
        if (block_id != constants.BlockId.AIR) {
            self.is_empty = false;
        }
    }

    /// Ensure data storage is allocated for current palette type
    fn ensureDataCapacity(self: *Self) !void {
        if (self.block_data.palette_type != self.block_palette.palette_type) {
            // Need to upgrade data storage
            const old_data = self.block_data;
            self.block_data = try PaletteData.init(self.allocator, self.block_palette.palette_type);

            // Copy old data if any
            if (old_data.palette_type != .empty) {
                for (0..constants.SECTION_BLOCK_COUNT) |i| {
                    const val = old_data.get(@intCast(i));
                    self.block_data.set(@intCast(i), val);
                }
            }

            if (old_data.data.len > 0) {
                self.allocator.free(old_data.data);
            }
        }
    }

    /// Serialize section data for network transmission
    /// Format from BlockSection.java lines 710-730:
    /// [1 byte] block palette type
    /// [palette data] block palette
    /// [block data] block indices
    /// [1 byte] filler palette type
    /// [palette data] filler palette
    /// [filler data] filler indices
    /// [1 byte] rotation palette type
    /// [palette data] rotation palette
    /// [rotation data] rotation indices
    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        // Calculate total size
        var size: usize = 0;

        // Block palette type + palette + data
        size += 1; // type byte
        size += self.block_palette.serializedSize();
        size += self.block_data.data.len;

        // Filler palette type + palette + data
        size += 1;
        size += self.filler_palette.serializedSize();
        size += self.filler_data.data.len;

        // Rotation palette type + palette + data
        size += 1;
        size += self.rotation_palette.serializedSize();
        size += self.rotation_data.data.len;

        // Allocate buffer
        const buf = try allocator.alloc(u8, size);
        errdefer allocator.free(buf);

        var offset: usize = 0;

        // Write block palette type
        buf[offset] = @intFromEnum(self.block_palette.palette_type);
        offset += 1;

        // Write block palette
        offset += try self.block_palette.serialize(buf[offset..]);

        // Write block data
        if (self.block_data.data.len > 0) {
            @memcpy(buf[offset .. offset + self.block_data.data.len], self.block_data.data);
            offset += self.block_data.data.len;
        }

        // Write filler palette type
        buf[offset] = @intFromEnum(self.filler_palette.palette_type);
        offset += 1;

        // Write filler palette
        offset += try self.filler_palette.serialize(buf[offset..]);

        // Write filler data
        if (self.filler_data.data.len > 0) {
            @memcpy(buf[offset .. offset + self.filler_data.data.len], self.filler_data.data);
            offset += self.filler_data.data.len;
        }

        // Write rotation palette type
        buf[offset] = @intFromEnum(self.rotation_palette.palette_type);
        offset += 1;

        // Write rotation palette
        offset += try self.rotation_palette.serialize(buf[offset..]);

        // Write rotation data
        if (self.rotation_data.data.len > 0) {
            @memcpy(buf[offset .. offset + self.rotation_data.data.len], self.rotation_data.data);
            offset += self.rotation_data.data.len;
        }

        return buf[0..offset];
    }

    /// Create an empty (all air) section for serialization
    pub fn serializeEmpty(allocator: std.mem.Allocator) ![]u8 {
        // Empty section: 3 bytes (one for each palette type = empty)
        // Plus minimal palette data (1 varint = 0 for each)
        const buf = try allocator.alloc(u8, 6);

        // Block palette: empty type + 0 entries
        buf[0] = @intFromEnum(PaletteType.empty);
        buf[1] = 0; // 0 entries

        // Filler palette: empty type + 0 entries
        buf[2] = @intFromEnum(PaletteType.empty);
        buf[3] = 0;

        // Rotation palette: empty type + 0 entries
        buf[4] = @intFromEnum(PaletteType.empty);
        buf[5] = 0;

        return buf;
    }
};

test "section basic operations" {
    const allocator = std.testing.allocator;

    var section = Section.init(allocator);
    defer section.deinit();

    // Initially empty
    try std.testing.expectEqual(@as(u16, 0), section.getBlock(0, 0, 0));
    try std.testing.expect(section.is_empty);

    // Set a block
    try section.setBlock(5, 10, 15, constants.BlockId.STONE);
    try std.testing.expectEqual(constants.BlockId.STONE, section.getBlock(5, 10, 15));
    try std.testing.expect(!section.is_empty);

    // Other positions still air
    try std.testing.expectEqual(constants.BlockId.AIR, section.getBlock(0, 0, 0));
}

test "section fill operations" {
    const allocator = std.testing.allocator;

    var section = Section.init(allocator);
    defer section.deinit();

    // Fill entire section with stone
    try section.fill(constants.BlockId.STONE);
    try std.testing.expectEqual(constants.BlockId.STONE, section.getBlock(0, 0, 0));
    try std.testing.expectEqual(constants.BlockId.STONE, section.getBlock(31, 31, 31));

    // Fill a single layer with dirt
    try section.fillLayer(16, constants.BlockId.DIRT);
    try std.testing.expectEqual(constants.BlockId.DIRT, section.getBlock(0, 16, 0));
    try std.testing.expectEqual(constants.BlockId.DIRT, section.getBlock(31, 16, 31));
    try std.testing.expectEqual(constants.BlockId.STONE, section.getBlock(0, 15, 0));
    try std.testing.expectEqual(constants.BlockId.STONE, section.getBlock(0, 17, 0));
}

test "section serialization" {
    const allocator = std.testing.allocator;

    var section = Section.init(allocator);
    defer section.deinit();

    // Fill with stone
    try section.fill(constants.BlockId.STONE);

    // Serialize
    const data = try section.serialize(allocator);
    defer allocator.free(data);

    // Should have non-zero length
    try std.testing.expect(data.len > 0);

    // First byte should be palette type
    const block_type: PaletteType = @enumFromInt(data[0]);
    try std.testing.expect(block_type != .empty); // Not empty since we filled it
}
