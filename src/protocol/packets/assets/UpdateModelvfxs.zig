/// UpdateModelvfxs Packet (ID 53)
///
/// Sends model VFX definitions to the client.
/// Uses int-keyed dictionary.

const std = @import("std");
const serializer = @import("serializer.zig");
const model_vfx = @import("../../../assets/types/model_vfx.zig");

pub const ModelVFXAsset = model_vfx.ModelVFXAsset;
pub const SwitchTo = model_vfx.SwitchTo;
pub const EffectDirection = model_vfx.EffectDirection;
pub const LoopOption = model_vfx.LoopOption;
pub const CurveType = model_vfx.CurveType;

// Constants from Java UpdateModelvfxs.java
pub const PACKET_ID: u32 = 53;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// ModelVFX entry for serialization (int-keyed)
pub const ModelVFXEntry = struct {
    id: i32,
    vfx: ModelVFXAsset,
};

/// Serialize UpdateModelvfxs packet
/// Format (int-keyed dictionary):
/// - nullBits (1 byte): bit 0 = modelVFXs dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes): i32 LE
/// - If bit 0 set: VarInt count + for each: i32 key + ModelVFX data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: []const ModelVFXEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = modelVFXs present
    const null_bits: u8 = if (entries.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, max_id, .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // modelVFXs dictionary (if present)
    if (entries.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + ModelVFX data
        for (entries) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, entry.id, .little);
            try buf.appendSlice(allocator, &key_bytes);

            // ModelVFX data
            const vfx_data = try entry.vfx.serialize(allocator);
            defer allocator.free(vfx_data);
            try buf.appendSlice(allocator, vfx_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (7 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
}

test "UpdateModelvfxs empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
}

test "UpdateModelvfxs with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]ModelVFXEntry{
        .{ .id = 1, .vfx = .{ .id = "highlight_effect", .switch_to = .appear } },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Should have header (6 bytes) + VarInt(1) + entry
    try std.testing.expect(pkt.len > 7);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check maxId = 1
    const max_id = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 1), max_id);
}
