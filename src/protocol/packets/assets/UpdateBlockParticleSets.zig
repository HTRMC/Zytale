/// UpdateBlockParticleSets Packet (ID 44)
///
/// Sends block particle set definitions to the client.
/// TODO: Implement full serialization

const std = @import("std");
const serializer = @import("serializer.zig");

// Constants from Java UpdateBlockParticleSets.java
pub const PACKET_ID: u32 = 44;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

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
