/// UpdateBlockParticleSets Packet (ID 44)
///
/// Sends block particle set definitions to the client.
/// Uses string-keyed dictionary (not int-keyed).

const std = @import("std");
const serializer = @import("serializer.zig");
const block_particle_set = @import("../../../assets/types/block_particle_set.zig");

pub const BlockParticleSetAsset = block_particle_set.BlockParticleSetAsset;
pub const BlockParticleEvent = block_particle_set.BlockParticleEvent;

// Constants from Java UpdateBlockParticleSets.java
pub const PACKET_ID: u32 = 44;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 2;
pub const MAX_SIZE: u32 = 1677721600;

/// BlockParticleSet entry for serialization (string-keyed)
pub const BlockParticleSetEntry = struct {
    key: []const u8,
    particle_set: BlockParticleSetAsset,
};

/// Serialize UpdateBlockParticleSets packet
/// Format (string-keyed dictionary):
/// - nullBits (1 byte): bit 0 = blockParticleSets dictionary present
/// - type (1 byte): UpdateType enum
/// - If bit 0 set: VarInt count + for each: VarString key + BlockParticleSet data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: []const BlockParticleSetEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = blockParticleSets present
    const null_bits: u8 = if (entries.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // blockParticleSets dictionary (if present)
    if (entries.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + BlockParticleSet data
        for (entries) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // BlockParticleSet data
            const ps_data = try entry.particle_set.serialize(allocator);
            defer allocator.free(ps_data);
            try buf.appendSlice(allocator, ps_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (3 bytes)
/// FIXED=2: nullBits(1) + type(1) + VarInt 0(1) = 3 bytes (no maxId)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 3);
    buf[0] = 0x01; // nullBits: dictionary present
    buf[1] = 0x00; // type = Init
    buf[2] = 0x00; // VarInt count = 0
    return buf;
}

test "UpdateBlockParticleSets empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
}

test "UpdateBlockParticleSets with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]BlockParticleSetEntry{
        .{ .key = "grass_particles", .particle_set = .{ .id = "grass_particles", .scale = 1.0 } },
    };

    const pkt = try serialize(allocator, .init, &entries);
    defer allocator.free(pkt);

    // Should have header + 1 particle set
    try std.testing.expect(pkt.len > 3);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);
}
