/// UpdateAudioCategories Packet (ID 80)
///
/// Sends audio category definitions to the client.
/// Each category defines a volume level for a group of sounds.

const std = @import("std");
const serializer = @import("serializer.zig");
const AudioCategoryAsset = @import("../../../assets/types/audio_category.zig").AudioCategoryAsset;

// Constants matching Java UpdateAudioCategories.java
pub const PACKET_ID: u32 = 80;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// AudioCategory entry for serialization
pub const AudioCategoryEntry = struct {
    id: []const u8,
    volume: f32,
};

/// Serialize AudioCategory entry: nullBits(1) + volume(4) + optional id VarString
pub fn serializeEntry(allocator: std.mem.Allocator, entry: *const AudioCategoryEntry, writer: *std.ArrayListUnmanaged(u8)) !void {
    // nullBits: bit 0 = id present
    const has_id: u8 = if (entry.id.len > 0) 0x01 else 0x00;
    try writer.append(allocator, has_id);

    // volume (f32 LE)
    try serializer.writeF32(allocator, writer, entry.volume);

    // id (if present)
    if (entry.id.len > 0) {
        try serializer.writeVarString(allocator, writer, entry.id);
    }
}

/// Serialize full packet with entries
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: []const serializer.AssetSerializer(AudioCategoryEntry).IndexedEntry,
) ![]u8 {
    return serializer.AssetSerializer(AudioCategoryEntry).serialize(
        allocator,
        update_type,
        max_id,
        entries,
        &[_]u8{},
        serializeEntry,
    );
}

/// Build empty packet (7 bytes)
/// Format: nullBits(1) + type(1) + maxId(4) + VarInt(0)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
}

// ============================================================================
// Tests
// ============================================================================

test "UpdateAudioCategories empty packet size" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);

    // FIXED=6: nullBits(1) + type(1) + maxId(4) + VarInt 0(1) = 7 bytes
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0x00), pkt[6]); // VarInt count = 0
}

test "UpdateAudioCategories serialization" {
    const allocator = std.testing.allocator;

    const S = serializer.AssetSerializer(AudioCategoryEntry);
    const entries = [_]S.IndexedEntry{
        .{ .index = 0, .value = .{ .id = "sfx", .volume = 1.0 } },
        .{ .index = 1, .value = .{ .id = "music", .volume = 0.8 } },
    };

    const pkt = try serialize(allocator, .init, 2, &entries);
    defer allocator.free(pkt);

    // Check header
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: has entries
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, pkt[2..6], .little)); // maxId

    // Should have 2 entries encoded after the header
    try std.testing.expect(pkt.len > 6);
}
