/// ResourceType Asset
///
/// Represents a resource type (crafting materials, currencies, etc.).
/// Based on com/hypixel/hytale/protocol/ResourceType.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// ResourceType asset
/// Fixed: 1 (nullBits) + 8 (offset slots) = 9 bytes
pub const ResourceTypeAsset = struct {
    id: ?[]const u8 = null,
    icon: ?[]const u8 = null,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 1;
    pub const VARIABLE_FIELD_COUNT: u32 = 2;
    pub const VARIABLE_BLOCK_START: u32 = 9;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.icon != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Offset slots (2 x 4 bytes = 8 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const icon_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        // Write id string
        if (self.id) |id_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id_str);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], -1, .little);
        }

        // Write icon string
        if (self.icon) |icon_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[icon_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, icon_str);
        } else {
            std.mem.writeInt(i32, buf.items[icon_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }
};

// Helper functions
fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    try writeVarInt(buf, allocator, @intCast(str.len));
    try buf.appendSlice(allocator, str);
}

fn writeVarInt(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var v: u32 = @bitCast(value);
    while (v >= 0x80) {
        try buf.append(allocator, @truncate((v & 0x7F) | 0x80));
        v >>= 7;
    }
    try buf.append(allocator, @truncate(v));
}

test "ResourceTypeAsset serialization" {
    const allocator = std.testing.allocator;

    var resource = ResourceTypeAsset{
        .id = "gold",
        .icon = "icons/gold.png",
    };

    const data = try resource.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 9 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 9);

    // Check nullBits: id (0x01) + icon (0x02) = 0x03
    try std.testing.expectEqual(@as(u8, 0x03), data[0]);
}

test "ResourceTypeAsset id only" {
    const allocator = std.testing.allocator;

    var resource = ResourceTypeAsset{
        .id = "wood",
    };

    const data = try resource.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: id only (0x01)
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);
}
