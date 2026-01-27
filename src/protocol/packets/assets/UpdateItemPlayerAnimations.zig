/// UpdateItemPlayerAnimations Packet (ID 52)
///
/// Sends item player animation definitions to the client.
/// Uses string-keyed dictionary (Map<String, ItemPlayerAnimations>).

const std = @import("std");
const serializer = @import("serializer.zig");
const item_player_animations = @import("../../../assets/types/item_player_animations.zig");

pub const ItemPlayerAnimationsAsset = item_player_animations.ItemPlayerAnimationsAsset;

// Constants from Java UpdateItemPlayerAnimations.java
pub const PACKET_ID: u32 = 52;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 2;
pub const MAX_SIZE: u32 = 1677721600;

/// ItemPlayerAnimations entry for serialization (string-keyed)
pub const ItemPlayerAnimationsEntry = struct {
    key: []const u8,
    asset: ItemPlayerAnimationsAsset,
};

/// Serialize UpdateItemPlayerAnimations packet
/// Format (string-keyed dictionary, inline variable):
/// - nullBits (1 byte): bit 0 = dictionary present
/// - type (1 byte): UpdateType enum
/// - If bit 0 set: VarInt count + for each: VarString key + ItemPlayerAnimations data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: ?[]const ItemPlayerAnimationsEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = dictionary present
    const null_bits: u8 = if (entries != null) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // dictionary (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + ItemPlayerAnimations data
        for (ents) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // ItemPlayerAnimations data
            const asset_data = try entry.asset.serialize(allocator);
            defer allocator.free(asset_data);
            try buf.appendSlice(allocator, asset_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateItemPlayerAnimations empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 2), pkt.len);
}

test "UpdateItemPlayerAnimations with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]ItemPlayerAnimationsEntry{
        .{ .key = "sword", .asset = .{ .use_first_person_override = true } },
    };

    const pkt = try serialize(allocator, .init, &entries);
    defer allocator.free(pkt);

    // Header (2 bytes) + VarInt(1) + key "sword" (1+5) + ItemPlayerAnimations (103 bytes)
    // 2 + 1 + 6 + 103 = 112 bytes
    try std.testing.expectEqual(@as(usize, 112), pkt.len);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);
}
