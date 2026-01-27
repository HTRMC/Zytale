/// UpdateTranslations Packet (ID 64)
///
/// Sends translation key->value pairs to the client.
/// Uses string-keyed dictionary with string values.

const std = @import("std");
const serializer = @import("serializer.zig");

// Constants from Java UpdateTranslations.java
pub const PACKET_ID: u32 = 64;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 2;
pub const MAX_SIZE: u32 = 1677721600;

/// Translation entry (key->value string pair)
pub const TranslationEntry = struct {
    key: []const u8,
    value: []const u8,
};

/// Serialize UpdateTranslations packet
/// Format (string-keyed dictionary with string values):
/// - nullBits (1 byte): bit 0 = translations dictionary present
/// - type (1 byte): UpdateType enum
/// - If bit 0 set: VarInt count + for each: VarString key + VarString value
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: ?[]const TranslationEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = translations present
    const null_bits: u8 = if (entries != null) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // translations dictionary (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + VarString value
        for (ents) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // Value (VarString)
            const val_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.value.len));
            try buf.appendSlice(allocator, vi_buf[0..val_vi_len]);
            try buf.appendSlice(allocator, entry.value);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateTranslations empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 2), pkt.len);
}

test "UpdateTranslations with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]TranslationEntry{
        .{ .key = "ui.button.ok", .value = "OK" },
        .{ .key = "ui.button.cancel", .value = "Cancel" },
    };

    const pkt = try serialize(allocator, .init, &entries);
    defer allocator.free(pkt);

    // Should have header + 2 translation entries
    try std.testing.expect(pkt.len > 3);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check VarInt count = 2
    try std.testing.expectEqual(@as(u8, 0x02), pkt[2]);
}

test "UpdateTranslations single entry" {
    const allocator = std.testing.allocator;

    const entries = [_]TranslationEntry{
        .{ .key = "hello", .value = "world" },
    };

    const pkt = try serialize(allocator, .init, &entries);
    defer allocator.free(pkt);

    // nullBits(1) + type(1) + VarInt(1) + key_len(1) + "hello"(5) + val_len(1) + "world"(5) = 15 bytes
    try std.testing.expectEqual(@as(usize, 15), pkt.len);
}
