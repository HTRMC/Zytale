/// UpdateParticleSpawners Packet (ID 49)
///
/// Sends particle spawner definitions to the client.
/// TODO: Implement full serialization

const std = @import("std");
const serializer = @import("serializer.zig");

// Constants from Java UpdateParticleSpawners.java
pub const PACKET_ID: u32 = 49;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 10;
pub const MAX_SIZE: u32 = 1677721600;

/// Build empty packet (12 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 12);
    buf[0] = 0x03;
    buf[1] = 0x00;
    std.mem.writeInt(i32, buf[2..6], 0, .little);
    std.mem.writeInt(i32, buf[6..10], 1, .little);
    buf[10] = 0x00;
    buf[11] = 0x00;
    return buf;
}

test "UpdateParticleSpawners empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 12), pkt.len);
}
