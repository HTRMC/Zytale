/// UpdateSoundSets Packet (ID 79)
///
/// Sends sound set definitions to the client.

const std = @import("std");
const serializer = @import("serializer.zig");
const sound_set = @import("../../../assets/types/sound_set.zig");

pub const SoundSetAsset = sound_set.SoundSetAsset;
pub const SoundCategory = sound_set.SoundCategory;
pub const SoundEntry = sound_set.SoundEntry;

// Constants from Java UpdateSoundSets.java
pub const PACKET_ID: u32 = 79;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// SoundSet entry for serialization
pub const SoundSetEntry = struct {
    id: u32,
    sound_set: SoundSetAsset,
};

/// Serialize UpdateSoundSets packet
/// Format:
/// - nullBits (1 byte): bit 0 = soundSets dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes LE): maximum sound set ID
/// - If bit 0 set: VarInt count + for each: i32 key + SoundSet data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: u32,
    entries: []const SoundSetEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = soundSets present
    const null_bits: u8 = if (entries.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, @intCast(max_id), .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // soundSets dictionary (if present)
    if (entries.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + SoundSet data
        for (entries) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, @intCast(entry.id), .little);
            try buf.appendSlice(allocator, &key_bytes);

            // SoundSet data
            const ss_data = try entry.sound_set.serialize(allocator);
            defer allocator.free(ss_data);
            try buf.appendSlice(allocator, ss_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (7 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
}

test "UpdateSoundSets empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
}

test "UpdateSoundSets with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]SoundSetEntry{
        .{ .id = 0, .sound_set = .{ .id = "ambient_sounds", .category = .ambient } },
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
