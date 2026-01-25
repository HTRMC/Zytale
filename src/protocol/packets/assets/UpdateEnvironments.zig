/// UpdateEnvironments Packet (ID 61)
///
/// Sends world environment definitions to the client.
/// Environments define visual settings like water tint.

const std = @import("std");
const serializer = @import("serializer.zig");
const common = @import("../../../assets/types/common.zig");

pub const Color = common.Color;

// Constants matching Java UpdateEnvironments.java
pub const PACKET_ID: u32 = 61;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 7;
pub const VARIABLE_FIELD_COUNT: u32 = 3;
pub const VARIABLE_BLOCK_START: u32 = 19;
pub const MAX_SIZE: u32 = 1677721600;

/// Environment asset for serialization
pub const EnvironmentAsset = struct {
    id: []const u8,
    water_tint: ?Color = null,
    // Simplified: omit fluidParticles and tagIndexes for now
};

/// Serialize Environment entry (simplified)
/// Format: nullBits(1) + waterTint(3) + idOffset(4) + fluidParticlesOffset(4) + tagIndexesOffset(4) + variable
pub fn serializeEntry(allocator: std.mem.Allocator, entry: *const EnvironmentAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    var null_bits: u8 = 0;
    if (entry.id.len > 0) null_bits |= 0x01;
    if (entry.water_tint != null) null_bits |= 0x02;

    try writer.append(allocator, null_bits);

    // waterTint (3 bytes) - always written, zeroed if null
    if (entry.water_tint) |tint| {
        try writer.append(allocator, tint.r);
        try writer.append(allocator, tint.g);
        try writer.append(allocator, tint.b);
    } else {
        try writer.appendNTimes(allocator, 0, 3);
    }

    // Offset table: 3 x i32 = 12 bytes
    const offset_start = writer.items.len;
    try writer.appendNTimes(allocator, 0, 12); // Placeholder for offsets

    // Variable block
    const var_block_start = writer.items.len;

    // id offset
    if (entry.id.len > 0) {
        const id_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[offset_start..][0..4], id_offset, .little);
        try serializer.writeVarString(allocator, writer, entry.id);
    } else {
        std.mem.writeInt(i32, writer.items[offset_start..][0..4], -1, .little);
    }

    // fluidParticles offset (not implemented, set to -1)
    std.mem.writeInt(i32, writer.items[offset_start + 4 ..][0..4], -1, .little);

    // tagIndexes offset (not implemented, set to -1)
    std.mem.writeInt(i32, writer.items[offset_start + 8 ..][0..4], -1, .little);
}

/// Serialize full packet with entries
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: []const serializer.AssetSerializer(EnvironmentAsset).IndexedEntry,
) ![]u8 {
    // FIXED=7: needs 1 extra byte for rebuildMapGeometry boolean
    const extra_bytes = [_]u8{0}; // rebuildMapGeometry = false
    return serializer.AssetSerializer(EnvironmentAsset).serialize(
        allocator,
        update_type,
        max_id,
        entries,
        &extra_bytes,
        serializeEntry,
    );
}

/// Build empty packet (8 bytes)
/// FIXED=7: nullBits(1) + type(1) + maxId(4) + 1 boolean(1) + VarInt 0(1) = 8 bytes
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{0});
}

// ============================================================================
// Tests
// ============================================================================

test "UpdateEnvironments empty packet size" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);

    // FIXED=7: nullBits(1) + type(1) + maxId(4) + 1 boolean(1) + VarInt 0(1) = 8 bytes
    try std.testing.expectEqual(@as(usize, 8), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0), pkt[6]); // rebuildMapGeometry = false
    try std.testing.expectEqual(@as(u8, 0x00), pkt[7]); // VarInt count = 0
}
