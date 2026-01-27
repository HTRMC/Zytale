/// UpdateBlockSets Packet (ID 46)
///
/// Sends block set definitions to the client.
/// Uses string-keyed dictionary.

const std = @import("std");
const serializer = @import("serializer.zig");
const block_set = @import("../../../assets/types/block_set.zig");

pub const BlockSetAsset = block_set.BlockSetAsset;

// Constants from Java UpdateBlockSets.java
pub const PACKET_ID: u32 = 46;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 2;
pub const MAX_SIZE: u32 = 1677721600;

/// BlockSet entry for serialization (string-keyed)
pub const BlockSetEntry = struct {
    key: []const u8,
    block_set: BlockSetAsset,
};

/// Serialize UpdateBlockSets packet
/// Format (string-keyed dictionary):
/// - nullBits (1 byte): bit 0 = blockSets dictionary present
/// - type (1 byte): UpdateType enum
/// - If bit 0 set: VarInt count + for each: VarString key + BlockSet data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: ?[]const BlockSetEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = blockSets present
    const null_bits: u8 = if (entries != null) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // blockSets dictionary (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + BlockSet data
        for (ents) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // BlockSet data
            const set_data = try entry.block_set.serialize(allocator);
            defer allocator.free(set_data);
            try buf.appendSlice(allocator, set_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateBlockSets empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 2), pkt.len);
}

test "UpdateBlockSets with entries" {
    const allocator = std.testing.allocator;

    const blocks = [_]i32{ 1, 2, 3 };

    const entries = [_]BlockSetEntry{
        .{ .key = "stone_group", .block_set = .{ .name = "Stone Variants", .blocks = &blocks } },
    };

    const pkt = try serialize(allocator, .init, &entries);
    defer allocator.free(pkt);

    // Should have header + 1 block set
    try std.testing.expect(pkt.len > 3);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);
}
