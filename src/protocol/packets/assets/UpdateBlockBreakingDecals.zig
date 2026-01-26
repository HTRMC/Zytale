/// UpdateBlockBreakingDecals Packet (ID 45)
///
/// Sends block breaking decal definitions to the client.
/// Uses string-keyed dictionary.

const std = @import("std");
const serializer = @import("serializer.zig");
const block_breaking_decal = @import("../../../assets/types/block_breaking_decal.zig");

pub const BlockBreakingDecalAsset = block_breaking_decal.BlockBreakingDecalAsset;

// Constants from Java UpdateBlockBreakingDecals.java
pub const PACKET_ID: u32 = 45;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 2;
pub const MAX_SIZE: u32 = 1677721600;

/// BlockBreakingDecal entry for serialization (string-keyed)
pub const BlockBreakingDecalEntry = struct {
    key: []const u8,
    decal: BlockBreakingDecalAsset,
};

/// Serialize UpdateBlockBreakingDecals packet
/// Format (string-keyed dictionary):
/// - nullBits (1 byte): bit 0 = blockBreakingDecals dictionary present
/// - type (1 byte): UpdateType enum
/// - If bit 0 set: VarInt count + for each: VarString key + BlockBreakingDecal data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: []const BlockBreakingDecalEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = blockBreakingDecals present
    const null_bits: u8 = if (entries.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // blockBreakingDecals dictionary (if present)
    if (entries.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + BlockBreakingDecal data
        for (entries) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // BlockBreakingDecal data
            const decal_data = try entry.decal.serialize(allocator);
            defer allocator.free(decal_data);
            try buf.appendSlice(allocator, decal_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (3 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 3);
    buf[0] = 0x01; // nullBits: dictionary present
    buf[1] = 0x00; // type = Init
    buf[2] = 0x00; // VarInt count = 0
    return buf;
}

test "UpdateBlockBreakingDecals empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
}

test "UpdateBlockBreakingDecals with entries" {
    const allocator = std.testing.allocator;

    const textures = [_][]const u8{
        "break_1.png",
        "break_2.png",
    };

    const entries = [_]BlockBreakingDecalEntry{
        .{ .key = "default", .decal = .{ .stage_textures = &textures } },
    };

    const pkt = try serialize(allocator, .init, &entries);
    defer allocator.free(pkt);

    // Should have header + 1 decal
    try std.testing.expect(pkt.len > 3);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);
}
