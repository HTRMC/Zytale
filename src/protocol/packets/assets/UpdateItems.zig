/// UpdateItems Packet (ID 54)
///
/// Sends item definitions to the client.
/// Uses string-keyed dictionary with offset-based variable fields.

const std = @import("std");
const serializer = @import("serializer.zig");
const item_base = @import("../../../assets/types/item_base.zig");

pub const ItemBaseAsset = item_base.ItemBaseAsset;

// Constants from Java UpdateItems.java
pub const PACKET_ID: u32 = 54;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 4;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 12;
pub const MAX_SIZE: u32 = 1677721600;

/// Item entry for serialization (string-keyed)
pub const ItemEntry = struct {
    key: []const u8,
    item: ItemBaseAsset,
};

/// Serialize UpdateItems packet
/// Format (offset-based variable fields):
/// - nullBits (1 byte): bit 0 = items present, bit 1 = removedItems present
/// - type (1 byte): UpdateType enum
/// - updateModels (1 byte): bool
/// - updateIcons (1 byte): bool
/// - itemsOffset (4 bytes): i32 LE offset to dictionary data
/// - removedItemsOffset (4 bytes): i32 LE offset to removed array
/// - Variable block: dictionary, removed array
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    update_models: bool,
    update_icons: bool,
    entries: []const ItemEntry,
    removed_items: ?[]const []const u8,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits
    var null_bits: u8 = 0;
    if (entries.len > 0) null_bits |= 0x01;
    if (removed_items != null and removed_items.?.len > 0) null_bits |= 0x02;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // updateModels, updateIcons
    try buf.append(allocator, if (update_models) @as(u8, 1) else 0);
    try buf.append(allocator, if (update_icons) @as(u8, 1) else 0);

    // Reserve offset slots (8 bytes)
    const items_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const removed_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const var_block_start = buf.items.len;

    // items dictionary (if present)
    if (entries.len > 0) {
        const offset: i32 = @intCast(buf.items.len - var_block_start);
        std.mem.writeInt(i32, buf.items[items_offset_slot..][0..4], offset, .little);

        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + ItemBase data
        for (entries) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // ItemBase data
            const item_data = try entry.item.serialize(allocator);
            defer allocator.free(item_data);
            try buf.appendSlice(allocator, item_data);
        }
    } else {
        std.mem.writeInt(i32, buf.items[items_offset_slot..][0..4], -1, .little);
    }

    // removedItems array (if present)
    if (removed_items) |removed| {
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

/// Build empty packet (14 bytes)
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

test "UpdateItems with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]ItemEntry{
        .{ .key = "test_item", .item = ItemBaseAsset.simple("test_item") },
    };

    const pkt = try serialize(allocator, .init, false, false, &entries, null);
    defer allocator.free(pkt);

    // Check nullBits has items present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check items offset is 0
    const items_offset = std.mem.readInt(i32, pkt[4..8], .little);
    try std.testing.expectEqual(@as(i32, 0), items_offset);

    // Check removed offset is -1
    const removed_offset = std.mem.readInt(i32, pkt[8..12], .little);
    try std.testing.expectEqual(@as(i32, -1), removed_offset);
}
