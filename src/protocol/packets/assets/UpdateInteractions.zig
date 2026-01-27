/// UpdateInteractions Packet (ID 66)
///
/// Sends interaction definitions to the client.
/// Uses int-keyed dictionary with inline variable fields.

const std = @import("std");
const serializer = @import("serializer.zig");
const interaction = @import("../../../assets/types/interaction.zig");

pub const InteractionAsset = interaction.InteractionAsset;

// Constants from Java UpdateInteractions.java
pub const PACKET_ID: u32 = 66;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// Interaction entry for serialization (int-keyed)
pub const InteractionEntry = struct {
    id: i32,
    interaction: InteractionAsset,
};

/// Serialize UpdateInteractions packet
/// Format (int-keyed dictionary, inline variable):
/// - nullBits (1 byte): bit 0 = interactions present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes): i32 LE
/// - Inline variable: VarInt count + entries (key i32 + Interaction data)
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: ?[]const InteractionEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits
    var null_bits: u8 = 0;
    if (entries != null) null_bits |= 0x01;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, max_id, .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // interactions (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + Interaction data
        for (ents) |entry| {
            // Key
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, entry.id, .little);
            try buf.appendSlice(allocator, &key_bytes);

            // Interaction data (polymorphic)
            const interaction_data = try entry.interaction.serialize(allocator);
            defer allocator.free(interaction_data);
            try buf.appendSlice(allocator, interaction_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateInteractions empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, 0, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 6), pkt.len);
}

test "UpdateInteractions with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]InteractionEntry{
        .{ .id = 1, .interaction = InteractionAsset.createSimple() },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Check nullBits has interactions present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check maxId is 1
    const max_id = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 1), max_id);

    // Check count is 1
    try std.testing.expectEqual(@as(u8, 1), pkt[6]);

    // Check key is 1
    const key = std.mem.readInt(i32, pkt[7..11], .little);
    try std.testing.expectEqual(@as(i32, 1), key);
}
