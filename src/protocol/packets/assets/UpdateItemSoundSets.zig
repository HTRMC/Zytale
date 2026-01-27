/// UpdateItemSoundSets Packet (ID 43)
///
/// Sends item sound set definitions to the client.

const std = @import("std");
const serializer = @import("serializer.zig");
const item_sound_set = @import("../../../assets/types/item_sound_set.zig");

pub const ItemSoundSetAsset = item_sound_set.ItemSoundSetAsset;
pub const ItemSoundEvent = item_sound_set.ItemSoundEvent;
pub const ItemSoundEventEntry = item_sound_set.ItemSoundEventEntry;

// Constants from Java UpdateItemSoundSets.java
pub const PACKET_ID: u32 = 43;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// ItemSoundSet entry for serialization
pub const ItemSoundSetEntry = struct {
    id: u32,
    sound_set: ItemSoundSetAsset,
};

/// Serialize UpdateItemSoundSets packet
/// Format:
/// - nullBits (1 byte): bit 0 = itemSoundSets dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes LE): maximum sound set ID
/// - If bit 0 set: VarInt count + for each: i32 key + ItemSoundSet data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: u32,
    entries: ?[]const ItemSoundSetEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = itemSoundSets present
    const null_bits: u8 = if (entries != null) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, @intCast(max_id), .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // itemSoundSets dictionary (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + ItemSoundSet data
        for (ents) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, @intCast(entry.id), .little);
            try buf.appendSlice(allocator, &key_bytes);

            // ItemSoundSet data
            const ss_data = try entry.sound_set.serialize(allocator);
            defer allocator.free(ss_data);
            try buf.appendSlice(allocator, ss_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateItemSoundSets empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, 0, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 6), pkt.len);
}

test "UpdateItemSoundSets with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]ItemSoundSetEntry{
        .{ .id = 0, .sound_set = .{ .id = "default_sounds" } },
    };

    const pkt = try serialize(allocator, .init, 0, &entries);
    defer allocator.free(pkt);

    // Should have header + 1 sound set
    try std.testing.expect(pkt.len > 7);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);
}
