/// UpdateTrails Packet (ID 51)
///
/// Sends trail effect definitions to the client.
/// Trails are visual effects that follow entities/projectiles.
/// NOTE: This packet uses STRING keys, not integer indices!

const std = @import("std");
const serializer = @import("serializer.zig");
const trail = @import("../../../assets/types/trail.zig");

pub const TrailAsset = trail.TrailAsset;
pub const FXRenderMode = trail.FXRenderMode;
pub const EdgeData = trail.EdgeData;

// Constants matching Java UpdateTrails.java
pub const PACKET_ID: u32 = 51;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 61;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 69;
pub const MAX_SIZE: u32 = 1677721600;

/// Serialize Trail entry
/// Format from Java:
/// nullBits(1) + lifeSpan(4) + roll(4) + start Edge(9) + end Edge(9) + lightInfluence(4) +
/// renderMode(1) + intersectionHighlight(8) + smooth(1) + frameSize(8) + frameRange(8) +
/// frameLifeSpan(4) + idOffset(4) + textureOffset(4) + [variable]
///
/// Java nullBits mapping (correct):
/// - bit 0 (0x01) = start (Edge) present
/// - bit 1 (0x02) = end (Edge) present
/// - bit 2 (0x04) = intersectionHighlight present
/// - bit 3 (0x08) = frameSize present
/// - bit 4 (0x10) = frameRange present
/// - bit 5 (0x20) = id present
/// - bit 6 (0x40) = texture present
pub fn serializeEntry(allocator: std.mem.Allocator, entry: *const TrailAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    const entry_start = writer.items.len;

    // nullBits - MUST match Java bit mapping!
    var null_bits: u8 = 0;
    if (entry.start != null) null_bits |= 0x01; // bit 0
    if (entry.end != null) null_bits |= 0x02; // bit 1
    // bit 2 = intersectionHighlight (not implemented)
    // bit 3 = frameSize (not implemented)
    // bit 4 = frameRange (not implemented)
    if (entry.id.len > 0) null_bits |= 0x20; // bit 5
    if (entry.texture.len > 0) null_bits |= 0x40; // bit 6
    try writer.append(allocator, null_bits);

    // lifeSpan (i32)
    try serializer.writeI32(allocator, writer, entry.life_span);

    // roll (f32)
    try serializer.writeF32(allocator, writer, entry.roll);

    // start Edge (9 bytes) - nullBits(1) + color(4) + width(4)
    if (entry.start) |start| {
        // Edge nullBits: bit 0 = color present
        try writer.append(allocator, 0x01); // color always present
        // ColorAlpha (4 bytes RGBA)
        try writer.append(allocator, start.color.r);
        try writer.append(allocator, start.color.g);
        try writer.append(allocator, start.color.b);
        try writer.append(allocator, start.color.a);
        // width (f32)
        try serializer.writeF32(allocator, writer, start.size);
    } else {
        try writer.appendNTimes(allocator, 0, 9);
    }

    // end Edge (9 bytes)
    if (entry.end) |end| {
        try writer.append(allocator, 0x01);
        try writer.append(allocator, end.color.r);
        try writer.append(allocator, end.color.g);
        try writer.append(allocator, end.color.b);
        try writer.append(allocator, end.color.a);
        try serializer.writeF32(allocator, writer, end.size);
    } else {
        try writer.appendNTimes(allocator, 0, 9);
    }

    // lightInfluence (f32)
    try serializer.writeF32(allocator, writer, entry.light_influence);

    // renderMode (u8)
    try writer.append(allocator, @intFromEnum(entry.render_mode));

    // intersectionHighlight (8 bytes) - not implemented, write zeros
    try writer.appendNTimes(allocator, 0, 8);

    // smooth (bool)
    try writer.append(allocator, if (entry.smooth) @as(u8, 1) else @as(u8, 0));

    // frameSize Vector2i (8 bytes) - not implemented, write zeros
    try writer.appendNTimes(allocator, 0, 8);

    // frameRange Range (8 bytes) - not implemented, write zeros
    try writer.appendNTimes(allocator, 0, 8);

    // frameLifeSpan (i32)
    try serializer.writeI32(allocator, writer, entry.frame_life_span);

    // idOffset placeholder (4 bytes) - offset 61
    const id_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // textureOffset placeholder (4 bytes) - offset 65
    const texture_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // Variable block starts at offset 69 from entry_start
    const var_block_start = entry_start + 69;

    // id VarString (if present)
    if (entry.id.len > 0) {
        const id_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[id_offset_pos..][0..4], id_offset, .little);
        try serializer.writeVarString(allocator, writer, entry.id);
    } else {
        std.mem.writeInt(i32, writer.items[id_offset_pos..][0..4], -1, .little);
    }

    // texture VarString (if present)
    if (entry.texture.len > 0) {
        const texture_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[texture_offset_pos..][0..4], texture_offset, .little);
        try serializer.writeVarString(allocator, writer, entry.texture);
    } else {
        std.mem.writeInt(i32, writer.items[texture_offset_pos..][0..4], -1, .little);
    }
}

/// Serialize full packet with entries (STRING-KEYED!)
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: []const serializer.StringKeyedSerializer(TrailAsset).StringKeyedEntry,
) ![]u8 {
    return serializer.StringKeyedSerializer(TrailAsset).serialize(
        allocator,
        update_type,
        entries,
        serializeEntry,
    );
}

/// Build empty packet (3 bytes - string-keyed)
/// Format: nullBits(1) + type(1) + VarInt(0)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyStringKeyedUpdate(allocator, .init);
}

// ============================================================================
// Tests
// ============================================================================

test "UpdateTrails empty packet size" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);

    // String-keyed: nullBits(1) + type(1) + VarInt 0(1) = 3 bytes
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(u8, 0x00), pkt[2]); // VarInt count = 0
}

test "StringKeyedSerializer with zero entries produces valid empty dictionary" {
    const allocator = std.testing.allocator;

    const S = serializer.StringKeyedSerializer(TrailAsset);
    const entries = [_]S.StringKeyedEntry{};

    const pkt = try S.serialize(
        allocator,
        .init,
        &entries,
        serializeEntry,
    );
    defer allocator.free(pkt);

    // Must be 3 bytes: nullBits(1) + type(1) + VarInt count 0(1)
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: dictionary IS present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[2]); // VarInt count = 0 (empty dictionary)
}
