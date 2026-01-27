const std = @import("std");
const constants = @import("constants.zig");
const varint = @import("../net/packet/varint.zig");

/// Palette types from PaletteType.java
/// Determines how block data is stored in a section
pub const PaletteType = enum(u8) {
    /// Section is empty (all air) - no data storage needed
    empty = 0,

    /// Up to 16 unique blocks - 4 bits per block (half-byte)
    half_byte = 1,

    /// Up to 256 unique blocks - 8 bits per block (1 byte)
    byte = 2,

    /// Up to 65536 unique blocks - 16 bits per block (2 bytes)
    short = 3,

    pub fn bitsPerEntry(self: PaletteType) u8 {
        return switch (self) {
            .empty => 0,
            .half_byte => 4,
            .byte => 8,
            .short => 16,
        };
    }

    pub fn maxEntries(self: PaletteType) u32 {
        return switch (self) {
            .empty => 0,
            .half_byte => 16,
            .byte => 256,
            .short => 65536,
        };
    }

    /// Calculate required data size for section (32768 blocks)
    pub fn dataSize(self: PaletteType) u32 {
        return switch (self) {
            .empty => 0,
            .half_byte => constants.SECTION_BLOCK_COUNT / 2, // 16384 bytes
            .byte => constants.SECTION_BLOCK_COUNT, // 32768 bytes
            .short => constants.SECTION_BLOCK_COUNT * 2, // 65536 bytes
        };
    }

    /// Determine appropriate palette type for a given number of unique blocks
    pub fn forUniqueCount(count: u32) PaletteType {
        if (count == 0 or count == 1) return .empty;
        if (count <= 16) return .half_byte;
        if (count <= 256) return .byte;
        return .short;
    }
};

/// Block palette - maps palette indices to actual block IDs
pub const BlockPalette = struct {
    allocator: std.mem.Allocator,
    palette_type: PaletteType,
    entries: std.ArrayList(u16),
    reverse_map: std.AutoHashMap(u16, u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .palette_type = .empty,
            .entries = .empty,
            .reverse_map = std.AutoHashMap(u16, u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit(self.allocator);
        self.reverse_map.deinit();
    }

    /// Add a block ID to the palette, returns palette index
    pub fn add(self: *Self, block_id: u16) !u8 {
        // Check if already in palette
        if (self.reverse_map.get(block_id)) |idx| {
            return idx;
        }

        // Add new entry
        const idx: u8 = @intCast(self.entries.items.len);
        try self.entries.append(self.allocator, block_id);
        try self.reverse_map.put(block_id, idx);

        // Update palette type if needed
        self.palette_type = PaletteType.forUniqueCount(@intCast(self.entries.items.len));

        return idx;
    }

    /// Get block ID from palette index
    pub fn get(self: *const Self, idx: u8) u16 {
        if (idx >= self.entries.items.len) return 0;
        return self.entries.items[idx];
    }

    /// Get palette index for a block ID
    pub fn indexOf(self: *const Self, block_id: u16) ?u8 {
        return self.reverse_map.get(block_id);
    }

    /// Reset palette to empty
    pub fn clear(self: *Self) void {
        self.entries.clearRetainingCapacity(self.allocator);
        self.reverse_map.clearRetainingCapacity();
        self.palette_type = .empty;
    }

    /// Serialize palette for network transmission (serializeForPacket format)
    /// Format from AbstractByteSectionPalette.serializeForPacket:
    /// [2 bytes LE] palette entry count
    /// For each entry:
    ///   [1 byte] internal ID (palette index)
    ///   [4 bytes LE] external block ID
    ///   [2 bytes LE] count of this block (we use 0 since we don't track counts)
    /// Note: For empty palette, nothing is written (handled by EmptySectionPalette)
    pub fn serialize(self: *const Self, buf: []u8) !usize {
        // Empty palette writes nothing
        if (self.palette_type == .empty or self.entries.items.len == 0) {
            return 0;
        }

        var offset: usize = 0;

        // Write entry count (2 bytes LE)
        const count: u16 = @intCast(self.entries.items.len);
        std.mem.writeInt(u16, buf[offset..][0..2], count, .little);
        offset += 2;

        // Write each palette entry
        for (self.entries.items, 0..) |block_id, idx| {
            // Internal ID (1 byte)
            buf[offset] = @intCast(idx);
            offset += 1;

            // External block ID (4 bytes LE)
            std.mem.writeInt(u32, buf[offset..][0..4], @as(u32, block_id), .little);
            offset += 4;

            // Block count (2 bytes LE) - we don't track this, use 0
            std.mem.writeInt(u16, buf[offset..][0..2], 0, .little);
            offset += 2;
        }

        return offset;
    }

    /// Calculate serialized size
    pub fn serializedSize(self: *const Self) usize {
        // Empty palette writes nothing
        if (self.palette_type == .empty or self.entries.items.len == 0) {
            return 0;
        }
        // 2 bytes for count + 7 bytes per entry (1 internal + 4 external + 2 count)
        return 2 + (self.entries.items.len * 7);
    }
};

/// Section palette data - compressed block storage
pub const PaletteData = struct {
    allocator: std.mem.Allocator,
    palette_type: PaletteType,
    data: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, palette_type: PaletteType) !Self {
        const size = palette_type.dataSize();
        const data: []u8 = if (size > 0) try allocator.alloc(u8, size) else &.{};

        return .{
            .allocator = allocator,
            .palette_type = palette_type,
            .data = data,
        };
    }

    pub fn initEmpty(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .palette_type = .empty,
            .data = &.{},
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
    }

    /// Set value at block index
    pub fn set(self: *Self, index: u32, value: u8) void {
        switch (self.palette_type) {
            .empty => {},
            .half_byte => {
                const byte_idx = index / 2;
                const shift: u3 = if (index % 2 == 0) 0 else 4;
                const mask: u8 = if (index % 2 == 0) 0xF0 else 0x0F;
                self.data[byte_idx] = (self.data[byte_idx] & mask) | (@as(u8, value & 0x0F) << shift);
            },
            .byte => {
                self.data[index] = value;
            },
            .short => {
                const idx = index * 2;
                std.mem.writeInt(u16, self.data[idx..][0..2], value, .little);
            },
        }
    }

    /// Get value at block index
    pub fn get(self: *const Self, index: u32) u8 {
        switch (self.palette_type) {
            .empty => return 0,
            .half_byte => {
                const byte_idx = index / 2;
                const shift: u3 = if (index % 2 == 0) 0 else 4;
                return (self.data[byte_idx] >> shift) & 0x0F;
            },
            .byte => {
                return self.data[index];
            },
            .short => {
                const idx = index * 2;
                return @truncate(std.mem.readInt(u16, self.data[idx..][0..2], .little));
            },
        }
    }

    /// Fill all entries with the same value
    pub fn fill(self: *Self, value: u8) void {
        switch (self.palette_type) {
            .empty => {},
            .half_byte => {
                const packed_value = (value & 0x0F) | (@as(u8, value & 0x0F) << 4);
                @memset(self.data, packed_value);
            },
            .byte => {
                @memset(self.data, value);
            },
            .short => {
                var i: usize = 0;
                while (i < self.data.len) : (i += 2) {
                    std.mem.writeInt(u16, self.data[i..][0..2], value, .little);
                }
            },
        }
    }
};

test "palette type calculations" {
    try std.testing.expectEqual(@as(u32, 0), PaletteType.empty.dataSize());
    try std.testing.expectEqual(@as(u32, 16384), PaletteType.half_byte.dataSize());
    try std.testing.expectEqual(@as(u32, 32768), PaletteType.byte.dataSize());
    try std.testing.expectEqual(@as(u32, 65536), PaletteType.short.dataSize());

    try std.testing.expectEqual(PaletteType.empty, PaletteType.forUniqueCount(0));
    try std.testing.expectEqual(PaletteType.empty, PaletteType.forUniqueCount(1));
    try std.testing.expectEqual(PaletteType.half_byte, PaletteType.forUniqueCount(2));
    try std.testing.expectEqual(PaletteType.half_byte, PaletteType.forUniqueCount(16));
    try std.testing.expectEqual(PaletteType.byte, PaletteType.forUniqueCount(17));
    try std.testing.expectEqual(PaletteType.byte, PaletteType.forUniqueCount(256));
    try std.testing.expectEqual(PaletteType.short, PaletteType.forUniqueCount(257));
}

test "block palette operations" {
    const allocator = std.testing.allocator;

    var palette = BlockPalette.init(allocator);
    defer palette.deinit();

    const idx0 = try palette.add(0); // Air
    const idx1 = try palette.add(1); // Bedrock
    const idx2 = try palette.add(2); // Stone

    try std.testing.expectEqual(@as(u8, 0), idx0);
    try std.testing.expectEqual(@as(u8, 1), idx1);
    try std.testing.expectEqual(@as(u8, 2), idx2);

    // Re-adding same block should return same index
    const idx1_again = try palette.add(1);
    try std.testing.expectEqual(@as(u8, 1), idx1_again);

    try std.testing.expectEqual(@as(u16, 0), palette.get(0));
    try std.testing.expectEqual(@as(u16, 1), palette.get(1));
    try std.testing.expectEqual(@as(u16, 2), palette.get(2));
}

test "palette data operations" {
    const allocator = std.testing.allocator;

    // Test half-byte palette
    var half_data = try PaletteData.init(allocator, .half_byte);
    defer half_data.deinit();

    half_data.set(0, 5);
    half_data.set(1, 10);
    half_data.set(2, 15);

    try std.testing.expectEqual(@as(u8, 5), half_data.get(0));
    try std.testing.expectEqual(@as(u8, 10), half_data.get(1));
    try std.testing.expectEqual(@as(u8, 15), half_data.get(2));

    // Test byte palette
    var byte_data = try PaletteData.init(allocator, .byte);
    defer byte_data.deinit();

    byte_data.set(0, 200);
    byte_data.set(100, 150);

    try std.testing.expectEqual(@as(u8, 200), byte_data.get(0));
    try std.testing.expectEqual(@as(u8, 150), byte_data.get(100));
}
