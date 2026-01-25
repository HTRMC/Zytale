/// UpdateBlockTypes Packet (ID 40)
///
/// Sends block type definitions to the client.
/// TODO: Implement full serialization

const std = @import("std");
const serializer = @import("serializer.zig");

// Constants from Java UpdateBlockTypes.java
pub const PACKET_ID: u32 = 40;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 10;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 10;
pub const MAX_SIZE: u32 = 1677721600;

// TODO: Implement full serialization
// pub fn serialize(...) !void { ... }

/// Build empty packet (11 bytes)
/// FIXED=10: nullBits(1) + type(1) + maxId(4) + 4 bools(4) + VarInt(1) = 11 bytes
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{ 0, 0, 0, 0 });
}

test "UpdateBlockTypes empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 11), pkt.len);
}
