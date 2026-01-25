/// UpdateTagPatterns Packet (ID 84)
///
/// Sends tag pattern definitions to the client.
/// Tag patterns are used for matching tags on entities/blocks.

const std = @import("std");
const serializer = @import("serializer.zig");
const TagPatternAsset = @import("../../../assets/types/tag_pattern.zig").TagPatternAsset;

// Constants matching Java UpdateTagPatterns.java
pub const PACKET_ID: u32 = 84;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 14;
pub const MAX_SIZE: u32 = 1677721600;

/// Serialize TagPattern entry
/// Format: nullBits(1) + type(1) + tagIndex(4) + operandsOffset(4) + notOffset(4) + [variable]
/// NOTE: TagPattern has NO id field in the protocol!
pub fn serializeEntry(allocator: std.mem.Allocator, entry: *const TagPatternAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    try serializeTagPatternRecursive(allocator, entry, writer);
}

fn serializeTagPatternRecursive(allocator: std.mem.Allocator, entry: *const TagPatternAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    const entry_start = writer.items.len;

    // nullBits: bit 0 = operands present, bit 1 = not present
    var null_bits: u8 = 0;
    if (entry.operands != null) null_bits |= 0x01;
    if (entry.not_pattern != null) null_bits |= 0x02;
    try writer.append(allocator, null_bits);

    // type (1 byte)
    try writer.append(allocator, @intFromEnum(entry.type));

    // tagIndex (4 bytes)
    try serializer.writeI32(allocator, writer, entry.tag_index);

    // operandsOffset placeholder (4 bytes) - offset 6
    const operands_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // notOffset placeholder (4 bytes) - offset 10
    const not_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // Variable block starts at offset 14 from entry_start
    const var_block_start = entry_start + 14;

    // operands (if present)
    if (entry.operands) |operands| {
        // Write offset relative to var_block_start
        const operands_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[operands_offset_pos..][0..4], operands_offset, .little);

        // Write VarInt count
        var count_buf: [5]u8 = undefined;
        const count_len = serializer.writeVarInt(&count_buf, @intCast(operands.len));
        try writer.appendSlice(allocator, count_buf[0..count_len]);

        // Write each operand recursively
        for (operands) |*op| {
            try serializeTagPatternRecursive(allocator, op, writer);
        }
    } else {
        std.mem.writeInt(i32, writer.items[operands_offset_pos..][0..4], -1, .little);
    }

    // not (if present)
    if (entry.not_pattern) |np| {
        // Write offset relative to var_block_start
        const not_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[not_offset_pos..][0..4], not_offset, .little);

        // Write the not pattern recursively
        try serializeTagPatternRecursive(allocator, np, writer);
    } else {
        std.mem.writeInt(i32, writer.items[not_offset_pos..][0..4], -1, .little);
    }
}

/// Serialize full packet with entries
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: []const serializer.AssetSerializer(TagPatternAsset).IndexedEntry,
) ![]u8 {
    return serializer.AssetSerializer(TagPatternAsset).serialize(
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

test "UpdateTagPatterns empty packet size" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);

    try std.testing.expectEqual(@as(usize, 7), pkt.len);
}
