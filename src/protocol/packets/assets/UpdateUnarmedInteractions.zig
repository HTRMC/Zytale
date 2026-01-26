/// UpdateUnarmedInteractions Packet (ID 68)
///
/// Sends unarmed interaction definitions to the client.
/// Uses enum-keyed dictionary (InteractionType -> i32) with inline variable.

const std = @import("std");
const serializer = @import("serializer.zig");
const interaction = @import("../../../assets/types/interaction.zig");

pub const InteractionType = interaction.InteractionType;

// Constants from Java UpdateUnarmedInteractions.java
pub const PACKET_ID: u32 = 68;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 2;
pub const MAX_SIZE: u32 = 20480007;

/// Unarmed interaction entry (InteractionType -> i32)
pub const UnarmedInteractionEntry = struct {
    interaction_type: InteractionType,
    value: i32,
};

/// Serialize UpdateUnarmedInteractions packet
/// Format (enum-keyed dictionary, inline variable):
/// - nullBits (1 byte): bit 0 = interactions present
/// - type (1 byte): UpdateType enum
/// - Inline variable: VarInt count + entries (InteractionType byte + i32 value)
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: []const UnarmedInteractionEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits
    var null_bits: u8 = 0;
    if (entries.len > 0) null_bits |= 0x01;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // interactions (if present)
    if (entries.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: InteractionType (1 byte) + i32 value (4 bytes)
        for (entries) |entry| {
            try buf.append(allocator, @intFromEnum(entry.interaction_type));
            var val_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &val_bytes, entry.value, .little);
            try buf.appendSlice(allocator, &val_bytes);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (3 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 3);
    buf[0] = 0x01; // nullBits: interactions present (empty dict)
    buf[1] = 0x00; // type = Init
    buf[2] = 0x00; // VarInt count = 0
    return buf;
}

test "UpdateUnarmedInteractions empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
}

test "UpdateUnarmedInteractions with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]UnarmedInteractionEntry{
        .{ .interaction_type = .primary, .value = 1 },
    };

    const pkt = try serialize(allocator, .init, &entries);
    defer allocator.free(pkt);

    // Check nullBits has interactions present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check count is 1
    try std.testing.expectEqual(@as(u8, 1), pkt[2]);

    // Check key is .primary (0)
    try std.testing.expectEqual(@as(u8, 0), pkt[3]);

    // Check value is 1
    const value = std.mem.readInt(i32, pkt[4..8], .little);
    try std.testing.expectEqual(@as(i32, 1), value);
}
