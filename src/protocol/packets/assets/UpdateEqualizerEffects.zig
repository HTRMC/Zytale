/// UpdateEqualizerEffects Packet (ID 82)
///
/// Sends equalizer effect definitions to the client.
/// Each effect defines audio EQ parameters.

const std = @import("std");
const serializer = @import("serializer.zig");
const EqualizerEffectAsset = @import("../../../assets/types/equalizer_effect.zig").EqualizerEffectAsset;

// Constants matching Java UpdateEqualizerEffects.java
pub const PACKET_ID: u32 = 82;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 41;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 41;
pub const MAX_SIZE: u32 = 1677721600;

/// Serialize EqualizerEffect entry
/// Format: nullBits(1) + 10 f32s(40) + [id VarString if nullBits & 1]
pub fn serializeEntry(allocator: std.mem.Allocator, entry: *const EqualizerEffectAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    // nullBits: bit 0 = id present
    const has_id: u8 = if (entry.id.len > 0) 0x01 else 0x00;
    try writer.append(allocator, has_id);

    // 10 f32 values (40 bytes) in exact order from Java
    try serializer.writeF32(allocator, writer, entry.low_gain);
    try serializer.writeF32(allocator, writer, entry.low_cut_off);
    try serializer.writeF32(allocator, writer, entry.low_mid_gain);
    try serializer.writeF32(allocator, writer, entry.low_mid_center);
    try serializer.writeF32(allocator, writer, entry.low_mid_width);
    try serializer.writeF32(allocator, writer, entry.high_mid_gain);
    try serializer.writeF32(allocator, writer, entry.high_mid_center);
    try serializer.writeF32(allocator, writer, entry.high_mid_width);
    try serializer.writeF32(allocator, writer, entry.high_gain);
    try serializer.writeF32(allocator, writer, entry.high_cut_off);

    // id VarString (inline, no offset!) - only if present
    if (entry.id.len > 0) {
        try serializer.writeVarString(allocator, writer, entry.id);
    }
}

/// Serialize full packet with entries
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: []const serializer.AssetSerializer(EqualizerEffectAsset).IndexedEntry,
) ![]u8 {
    return serializer.AssetSerializer(EqualizerEffectAsset).serialize(
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

test "UpdateEqualizerEffects empty packet size" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);

    try std.testing.expectEqual(@as(usize, 7), pkt.len);
}
