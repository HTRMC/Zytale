/// UpdateItemCategories Packet (ID 56)
///
/// Sends item category definitions to the client.

const std = @import("std");
const serializer = @import("serializer.zig");
const item_category = @import("../../../assets/types/item_category.zig");

pub const ItemCategoryAsset = item_category.ItemCategoryAsset;

// Constants from Java UpdateItemCategories.java
pub const PACKET_ID: u32 = 56;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 2;
pub const MAX_SIZE: u32 = 1677721600;

/// Serialize UpdateItemCategories packet
/// Format:
/// - nullBits (1 byte): bit 0 = itemCategories present
/// - type (1 byte): UpdateType enum
/// - If bit 0 set: VarInt count + array of ItemCategory
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    categories: []const ItemCategoryAsset,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = itemCategories present
    const null_bits: u8 = if (categories.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // itemCategories array (if present)
    if (categories.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(categories.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each category
        for (categories) |*cat| {
            const cat_data = try cat.serialize(allocator);
            defer allocator.free(cat_data);
            try buf.appendSlice(allocator, cat_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (3 bytes for empty array with VarInt 0)
/// Format: nullBits(1) + type(1) + VarInt(0) = 3 bytes
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 3);
    buf[0] = 0x01; // nullBits: array present (but empty)
    buf[1] = 0x00; // type: init
    buf[2] = 0x00; // VarInt: 0 elements
    return buf;
}

test "UpdateItemCategories empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
}

test "UpdateItemCategories with categories" {
    const allocator = std.testing.allocator;

    const categories = [_]ItemCategoryAsset{
        .{ .id = "weapons", .name = "Weapons", .order = 1 },
        .{ .id = "tools", .name = "Tools", .order = 2 },
    };

    const pkt = try serialize(allocator, .init, &categories);
    defer allocator.free(pkt);

    // Should have header + 2 categories
    try std.testing.expect(pkt.len > 3);

    // Check nullBits has array present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check VarInt count is 2
    try std.testing.expectEqual(@as(u8, 2), pkt[2]);
}
