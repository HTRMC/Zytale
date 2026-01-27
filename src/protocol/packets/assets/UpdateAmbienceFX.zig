/// UpdateAmbienceFX Packet (ID 62)
///
/// Sends ambience FX definitions to the client.
/// Uses int-keyed dictionary.

const std = @import("std");
const serializer = @import("serializer.zig");
const ambience_fx = @import("../../../assets/types/ambience_fx.zig");

pub const AmbienceFXAsset = ambience_fx.AmbienceFXAsset;

// Constants from Java UpdateAmbienceFX.java
pub const PACKET_ID: u32 = 62;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// AmbienceFX entry for serialization (int-keyed)
pub const AmbienceFXEntry = struct {
    id: i32,
    asset: AmbienceFXAsset,
};

/// Serialize UpdateAmbienceFX packet
/// Format (int-keyed dictionary):
/// - nullBits (1 byte): bit 0 = dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes): i32 LE
/// - If bit 0 set: VarInt count + for each: i32 key + AmbienceFX data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: ?[]const AmbienceFXEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = dictionary present
    const null_bits: u8 = if (entries != null) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, max_id, .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // dictionary (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + AmbienceFX data
        for (ents) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, entry.id, .little);
            try buf.appendSlice(allocator, &key_bytes);

            // AmbienceFX data
            const asset_data = try entry.asset.serialize(allocator);
            defer allocator.free(asset_data);
            try buf.appendSlice(allocator, asset_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateAmbienceFX empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, 0, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 6), pkt.len);
}

test "UpdateAmbienceFX with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]AmbienceFXEntry{
        .{ .id = 1, .asset = .{ .priority = 5 } },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Header (6 bytes) + VarInt(1) + 1 entry (4 + 42)
    // 6 + 1 + 46 = 53 bytes
    try std.testing.expectEqual(@as(usize, 53), pkt.len);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check maxId = 1
    const max_id = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 1), max_id);
}
