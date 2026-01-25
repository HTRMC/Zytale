/// UpdateItems Packet (ID 54)
///
/// Sends item definitions to the client.
/// TODO: Implement full serialization

const std = @import("std");
const serializer = @import("serializer.zig");

// Constants from Java UpdateItems.java
pub const PACKET_ID: u32 = 54;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 4;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 12;
pub const MAX_SIZE: u32 = 1677721600;

/// Build empty packet (14 bytes)
/// FIXED=4: nullBits + type + 2 booleans + offset table for 2 variable fields
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 14);
    buf[0] = 0x03; // nullBits: both fields present (items and removedItems)
    buf[1] = 0x00; // type = Init
    buf[2] = 0; // updateModels = false
    buf[3] = 0; // updateIcons = false
    // Offset to items (at variable block start = offset 0)
    std.mem.writeInt(i32, buf[4..8], 0, .little);
    // Offset to removedItems (after items VarInt 0 = offset 1)
    std.mem.writeInt(i32, buf[8..12], 1, .little);
    buf[12] = 0x00; // items count = 0
    buf[13] = 0x00; // removedItems count = 0
    return buf;
}

test "UpdateItems empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 14), pkt.len);
}
