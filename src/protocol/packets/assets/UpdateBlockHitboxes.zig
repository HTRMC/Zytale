/// UpdateBlockHitboxes Packet (ID 41)
///
/// Sends block hitbox definitions to the client.
/// Uses int-keyed dictionary with Hitbox arrays.

const std = @import("std");
const serializer = @import("serializer.zig");
const hitbox = @import("../../../assets/types/hitbox.zig");

pub const Hitbox = hitbox.Hitbox;

// Constants from Java UpdateBlockHitboxes.java
pub const PACKET_ID: u32 = 41;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// BlockHitbox entry for serialization (int-keyed)
pub const BlockHitboxEntry = struct {
    block_id: i32,
    hitboxes: []const Hitbox,
};

/// Serialize UpdateBlockHitboxes packet
/// Format (int-keyed dictionary):
/// - nullBits (1 byte): bit 0 = blockBaseHitboxes dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes): i32 LE
/// - If bit 0 set: VarInt count + for each: i32 key + VarInt array len + Hitbox[] data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: ?[]const BlockHitboxEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = blockBaseHitboxes present
    const null_bits: u8 = if (entries != null) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, max_id, .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // blockBaseHitboxes dictionary (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + VarInt array len + Hitbox[] data
        for (ents) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, entry.block_id, .little);
            try buf.appendSlice(allocator, &key_bytes);

            // VarInt array length
            const arr_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.hitboxes.len));
            try buf.appendSlice(allocator, vi_buf[0..arr_vi_len]);

            // Hitbox data (24 bytes each)
            for (entry.hitboxes) |*hb| {
                try hb.serialize(&buf, allocator);
            }
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateBlockHitboxes empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, 0, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 6), pkt.len);
}

test "UpdateBlockHitboxes with entries" {
    const allocator = std.testing.allocator;

    const hitboxes = [_]Hitbox{
        Hitbox.unitCube(),
    };

    const entries = [_]BlockHitboxEntry{
        .{ .block_id = 1, .hitboxes = &hitboxes },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Should have header (6 bytes) + VarInt(1) + entry (4 + 1 + 24)
    try std.testing.expect(pkt.len > 7);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check maxId = 1
    const max_id = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 1), max_id);
}
