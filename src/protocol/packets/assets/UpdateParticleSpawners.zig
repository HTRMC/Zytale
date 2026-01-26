/// UpdateParticleSpawners Packet (ID 50)
///
/// Sends particle spawner definitions to the client.
/// Uses string-keyed dictionary with offset-based variable fields.

const std = @import("std");
const serializer = @import("serializer.zig");
const particle_spawner = @import("../../../assets/types/particle_spawner.zig");

pub const ParticleSpawnerAsset = particle_spawner.ParticleSpawnerAsset;

// Constants from Java UpdateParticleSpawners.java
pub const PACKET_ID: u32 = 50;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 10;
pub const MAX_SIZE: u32 = 1677721600;

/// ParticleSpawner entry for serialization (string-keyed)
pub const ParticleSpawnerEntry = struct {
    key: []const u8,
    asset: ParticleSpawnerAsset,
};

/// Serialize UpdateParticleSpawners packet
/// Format (offset-based variable fields):
/// - nullBits (1 byte): bit 0 = particleSpawners present, bit 1 = removedParticleSpawners present
/// - type (1 byte): UpdateType enum
/// - particleSpawnersOffset (4 bytes): i32 LE offset to dictionary data
/// - removedParticleSpawnersOffset (4 bytes): i32 LE offset to removed array
/// - Variable block: dictionary, removed array
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: []const ParticleSpawnerEntry,
    removed_spawners: ?[]const []const u8,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits
    var null_bits: u8 = 0;
    if (entries.len > 0) null_bits |= 0x01;
    if (removed_spawners != null and removed_spawners.?.len > 0) null_bits |= 0x02;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // Reserve offset slots (8 bytes)
    const spawners_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const removed_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const var_block_start = buf.items.len;

    // particleSpawners dictionary (if present)
    if (entries.len > 0) {
        const offset: i32 = @intCast(buf.items.len - var_block_start);
        std.mem.writeInt(i32, buf.items[spawners_offset_slot..][0..4], offset, .little);

        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + ParticleSpawner data
        for (entries) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // ParticleSpawner data
            const asset_data = try entry.asset.serialize(allocator);
            defer allocator.free(asset_data);
            try buf.appendSlice(allocator, asset_data);
        }
    } else {
        std.mem.writeInt(i32, buf.items[spawners_offset_slot..][0..4], -1, .little);
    }

    // removedParticleSpawners array (if present)
    if (removed_spawners) |removed| {
        if (removed.len > 0) {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[removed_offset_slot..][0..4], offset, .little);

            // VarInt count
            var vi_buf: [5]u8 = undefined;
            const vi_len = serializer.writeVarInt(&vi_buf, @intCast(removed.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            // Each string
            for (removed) |name| {
                const name_vi_len = serializer.writeVarInt(&vi_buf, @intCast(name.len));
                try buf.appendSlice(allocator, vi_buf[0..name_vi_len]);
                try buf.appendSlice(allocator, name);
            }
        } else {
            std.mem.writeInt(i32, buf.items[removed_offset_slot..][0..4], -1, .little);
        }
    } else {
        std.mem.writeInt(i32, buf.items[removed_offset_slot..][0..4], -1, .little);
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (12 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 12);
    buf[0] = 0x03; // nullBits: both fields present (for empty arrays)
    buf[1] = 0x00; // type = Init
    std.mem.writeInt(i32, buf[2..6], 0, .little); // offset to field 0
    std.mem.writeInt(i32, buf[6..10], 1, .little); // offset to field 1
    buf[10] = 0x00; // field 0 count = 0
    buf[11] = 0x00; // field 1 count = 0
    return buf;
}

test "UpdateParticleSpawners empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 12), pkt.len);
}

test "UpdateParticleSpawners with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]ParticleSpawnerEntry{
        .{ .key = "fire", .asset = .{ .life_span = 5.0 } },
    };

    const pkt = try serialize(allocator, .init, &entries, null);
    defer allocator.free(pkt);

    // Check nullBits has spawners present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check spawners offset is 0
    const spawners_offset = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 0), spawners_offset);

    // Check removed offset is -1
    const removed_offset = std.mem.readInt(i32, pkt[6..10], .little);
    try std.testing.expectEqual(@as(i32, -1), removed_offset);
}
