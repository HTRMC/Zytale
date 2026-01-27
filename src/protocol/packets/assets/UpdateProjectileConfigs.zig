/// UpdateProjectileConfigs Packet (ID 85)
///
/// Sends projectile config definitions to the client.
/// Uses string-keyed dictionary with offset-based variable fields.

const std = @import("std");
const serializer = @import("serializer.zig");
const projectile_config = @import("../../../assets/types/projectile_config.zig");

pub const ProjectileConfigAsset = projectile_config.ProjectileConfigAsset;

// Constants from Java UpdateProjectileConfigs.java
pub const PACKET_ID: u32 = 85;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 10;
pub const MAX_SIZE: u32 = 1677721600;

/// ProjectileConfig entry for serialization (string-keyed)
pub const ProjectileConfigEntry = struct {
    key: []const u8,
    config: ProjectileConfigAsset,
};

/// Serialize UpdateProjectileConfigs packet
/// Format (offset-based variable fields):
/// - nullBits (1 byte): bit 0 = configs present, bit 1 = removedConfigs present
/// - type (1 byte): UpdateType enum
/// - configsOffset (4 bytes): i32 LE offset to dictionary data
/// - removedConfigsOffset (4 bytes): i32 LE offset to removed array
/// - Variable block: dictionary, removed array
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: ?[]const ProjectileConfigEntry,
    removed_configs: ?[]const []const u8,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits - matches Java: checks != null, not size > 0
    var null_bits: u8 = 0;
    if (entries != null) null_bits |= 0x01;
    if (removed_configs != null) null_bits |= 0x02;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // Reserve offset slots (8 bytes)
    const configs_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const removed_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const var_block_start = buf.items.len;

    // configs dictionary (if present)
    if (entries) |ents| {
        const offset: i32 = @intCast(buf.items.len - var_block_start);
        std.mem.writeInt(i32, buf.items[configs_offset_slot..][0..4], offset, .little);

        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + ProjectileConfig data
        for (ents) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // ProjectileConfig data
            const config_data = try entry.config.serialize(allocator);
            defer allocator.free(config_data);
            try buf.appendSlice(allocator, config_data);
        }
    } else {
        std.mem.writeInt(i32, buf.items[configs_offset_slot..][0..4], -1, .little);
    }

    // removedConfigs array (if present)
    if (removed_configs) |removed| {
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

    return buf.toOwnedSlice(allocator);
}

test "UpdateProjectileConfigs empty packet size" {
    const allocator = std.testing.allocator;
    // No buildEmptyPacket - just call serialize with null like Java
    const pkt = try serialize(allocator, .init, null, null);
    defer allocator.free(pkt);
    // Empty packet: nullBits(1) + type(1) + 2 offsets(8) = 10 bytes
    try std.testing.expectEqual(@as(usize, 10), pkt.len);
    // nullBits should be 0 (no fields present)
    try std.testing.expectEqual(@as(u8, 0x00), pkt[0]);
}

test "UpdateProjectileConfigs with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]ProjectileConfigEntry{
        .{ .key = "arrow", .config = .{ .launch_force = 10.0 } },
    };

    const pkt = try serialize(allocator, .init, &entries, null);
    defer allocator.free(pkt);

    // Check nullBits has configs present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check configs offset is 0
    const configs_offset = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 0), configs_offset);

    // Check removed offset is -1
    const removed_offset = std.mem.readInt(i32, pkt[6..10], .little);
    try std.testing.expectEqual(@as(i32, -1), removed_offset);
}
