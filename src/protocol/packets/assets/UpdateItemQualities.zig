/// UpdateItemQualities Packet (ID 55)
///
/// Sends item quality definitions to the client.

const std = @import("std");
const serializer = @import("serializer.zig");
const item_quality = @import("../../../assets/types/item_quality.zig");

pub const ItemQualityAsset = item_quality.ItemQualityAsset;

// Constants from Java UpdateItemQualities.java
pub const PACKET_ID: u32 = 55;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// ItemQuality entry for serialization
pub const ItemQualityEntry = struct {
    id: u32,
    quality: ItemQualityAsset,
};

/// Serialize UpdateItemQualities packet
/// Format:
/// - nullBits (1 byte): bit 0 = itemQualities dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes LE): maximum quality ID
/// - If bit 0 set: VarInt count + for each: i32 key + ItemQuality data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: u32,
    entries: []const ItemQualityEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = itemQualities present
    const null_bits: u8 = if (entries.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, @intCast(max_id), .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // itemQualities dictionary (if present)
    if (entries.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + ItemQuality data
        for (entries) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, @intCast(entry.id), .little);
            try buf.appendSlice(allocator, &key_bytes);

            // ItemQuality data
            const quality_data = try entry.quality.serialize(allocator);
            defer allocator.free(quality_data);
            try buf.appendSlice(allocator, quality_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (7 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
}

test "UpdateItemQualities empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
}

test "UpdateItemQualities with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]ItemQualityEntry{
        .{ .id = 0, .quality = .{ .id = "common", .visible_quality_label = true } },
    };

    const pkt = try serialize(allocator, .init, 0, &entries);
    defer allocator.free(pkt);

    // Should have header + 1 quality
    try std.testing.expect(pkt.len > 7);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);
}
