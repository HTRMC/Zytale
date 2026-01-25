/// UpdateItemPlayerAnimations Packet (ID 52)
///
/// Sends item player animation definitions to the client.
/// NOTE: This packet uses STRING keys (Map<String, ItemPlayerAnimations>)
/// TODO: Implement full serialization

const std = @import("std");
const serializer = @import("serializer.zig");

// Constants from Java UpdateItemPlayerAnimations.java
pub const PACKET_ID: u32 = 52;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// Build empty packet (3 bytes - string-keyed)
/// Format: nullBits(1) + type(1) + VarInt 0(1) = 3 bytes (no maxId!)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyStringKeyedUpdate(allocator, .init);
}

test "UpdateItemPlayerAnimations empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
}
