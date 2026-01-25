/// UpdateParticleSystems Packet (ID 48)
///
/// Sends particle system definitions to the client.
/// TODO: Implement full serialization

const std = @import("std");
const serializer = @import("serializer.zig");

// Constants from Java UpdateParticleSystems.java
pub const PACKET_ID: u32 = 48;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 10;
pub const MAX_SIZE: u32 = 1677721600;

/// Build empty packet (12 bytes)
/// FIXED=2 with 2 variable fields (need offset table)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 12);
    buf[0] = 0x03; // nullBits: both fields present
    buf[1] = 0x00; // type = Init
    std.mem.writeInt(i32, buf[2..6], 0, .little); // offset to field 0
    std.mem.writeInt(i32, buf[6..10], 1, .little); // offset to field 1
    buf[10] = 0x00; // field 0 count = 0
    buf[11] = 0x00; // field 1 count = 0
    return buf;
}

test "UpdateParticleSystems empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 12), pkt.len);
}
