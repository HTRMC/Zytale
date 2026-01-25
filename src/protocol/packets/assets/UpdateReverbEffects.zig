/// UpdateReverbEffects Packet (ID 81)
///
/// Sends reverb effect definitions to the client.
/// Each effect defines audio reverb parameters.

const std = @import("std");
const serializer = @import("serializer.zig");
const ReverbEffectAsset = @import("../../../assets/types/reverb_effect.zig").ReverbEffectAsset;

// Constants matching Java UpdateReverbEffects.java
pub const PACKET_ID: u32 = 81;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 54;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 54;
pub const MAX_SIZE: u32 = 1677721600;

/// Serialize ReverbEffect entry
/// Format: nullBits(1) + 13 f32s(52) + bool(1) + [id VarString if nullBits & 1]
pub fn serializeEntry(allocator: std.mem.Allocator, entry: *const ReverbEffectAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    // nullBits: bit 0 = id present
    const has_id: u8 = if (entry.id.len > 0) 0x01 else 0x00;
    try writer.append(allocator, has_id);

    // 13 f32 values (52 bytes) in exact order from Java
    try serializer.writeF32(allocator, writer, entry.dry_gain);
    try serializer.writeF32(allocator, writer, entry.modal_density);
    try serializer.writeF32(allocator, writer, entry.diffusion);
    try serializer.writeF32(allocator, writer, entry.gain);
    try serializer.writeF32(allocator, writer, entry.high_frequency_gain);
    try serializer.writeF32(allocator, writer, entry.decay_time);
    try serializer.writeF32(allocator, writer, entry.high_frequency_decay_ratio);
    try serializer.writeF32(allocator, writer, entry.reflection_gain);
    try serializer.writeF32(allocator, writer, entry.reflection_delay);
    try serializer.writeF32(allocator, writer, entry.late_reverb_gain);
    try serializer.writeF32(allocator, writer, entry.late_reverb_delay);
    try serializer.writeF32(allocator, writer, entry.room_rolloff_factor);
    try serializer.writeF32(allocator, writer, entry.air_absorption_hf_gain);

    // bool (1 byte)
    try writer.append(allocator, if (entry.limit_decay_high_frequency) @as(u8, 1) else @as(u8, 0));

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
    entries: []const serializer.AssetSerializer(ReverbEffectAsset).IndexedEntry,
) ![]u8 {
    return serializer.AssetSerializer(ReverbEffectAsset).serialize(
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

test "UpdateReverbEffects empty packet size" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);

    try std.testing.expectEqual(@as(usize, 7), pkt.len);
}
