/// BlockSet Asset
///
/// Represents a named set of block IDs.
/// Based on com/hypixel/hytale/protocol/BlockSet.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// BlockSet asset
/// Format: nullBits(1) + nameOffset(4) + blocksOffset(4) + variable data
pub const BlockSetAsset = struct {
    name: ?[]const u8 = null,
    blocks: ?[]const i32 = null,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 1;
    pub const VARIABLE_FIELD_COUNT: u32 = 2;
    pub const VARIABLE_BLOCK_START: u32 = 9;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.name != null) null_bits |= 0x01;
        if (self.blocks != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Offset slots (2 x 4 bytes = 8 bytes)
        const name_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const blocks_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        // Write name string
        if (self.name) |name_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[name_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, name_str);
        } else {
            std.mem.writeInt(i32, buf.items[name_offset_pos..][0..4], -1, .little);
        }

        // Write blocks array
        if (self.blocks) |block_ids| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[blocks_offset_pos..][0..4], offset, .little);

            // VarInt count
            try writeVarInt(&buf, allocator, @intCast(block_ids.len));

            // Each block ID (i32 LE)
            for (block_ids) |block_id| {
                var bytes: [4]u8 = undefined;
                std.mem.writeInt(i32, &bytes, block_id, .little);
                try buf.appendSlice(allocator, &bytes);
            }
        } else {
            std.mem.writeInt(i32, buf.items[blocks_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }
};

// Helper functions
fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    try writeVarInt(buf, allocator, @intCast(str.len));
    try buf.appendSlice(allocator, str);
}

fn writeVarInt(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var v: u32 = @bitCast(value);
    while (v >= 0x80) {
        try buf.append(allocator, @truncate((v & 0x7F) | 0x80));
        v >>= 7;
    }
    try buf.append(allocator, @truncate(v));
}

test "BlockSetAsset serialization" {
    const allocator = std.testing.allocator;

    const blocks = [_]i32{ 1, 2, 3, 4, 5 };

    var block_set = BlockSetAsset{
        .name = "stone_variants",
        .blocks = &blocks,
    };

    const data = try block_set.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 9 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 9);

    // Check nullBits: name (0x01) + blocks (0x02) = 0x03
    try std.testing.expectEqual(@as(u8, 0x03), data[0]);
}

test "BlockSetAsset name only" {
    const allocator = std.testing.allocator;

    var block_set = BlockSetAsset{
        .name = "empty_set",
    };

    const data = try block_set.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: name only (0x01)
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);
}

test "BlockSetAsset empty" {
    const allocator = std.testing.allocator;

    var block_set = BlockSetAsset{};

    const data = try block_set.serialize(allocator);
    defer allocator.free(data);

    // Should be 9 bytes (fixed block only)
    try std.testing.expectEqual(@as(usize, 9), data.len);

    // Check nullBits: nothing present (0x00)
    try std.testing.expectEqual(@as(u8, 0x00), data[0]);

    // Check offsets are -1
    const name_offset = std.mem.readInt(i32, data[1..5], .little);
    const blocks_offset = std.mem.readInt(i32, data[5..9], .little);
    try std.testing.expectEqual(@as(i32, -1), name_offset);
    try std.testing.expectEqual(@as(i32, -1), blocks_offset);
}
