/// ItemCategory Asset
///
/// Represents an item category for the inventory UI.
/// Based on com/hypixel/hytale/protocol/ItemCategory.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Display mode for items in grid
pub const ItemGridInfoDisplayMode = enum(u8) {
    tooltip = 0,
    // Add more as needed

    pub fn fromValue(value: u8) ItemGridInfoDisplayMode {
        return @enumFromInt(value);
    }
};

/// ItemCategory asset
pub const ItemCategoryAsset = struct {
    id: ?[]const u8 = null,
    name: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    order: i32 = 0,
    info_display_mode: ItemGridInfoDisplayMode = .tooltip,
    children: ?[]ItemCategoryAsset = null,

    const Self = @This();

    /// Protocol constants from Java
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 6;
    pub const VARIABLE_FIELD_COUNT: u32 = 4;
    pub const VARIABLE_BLOCK_START: u32 = 22;

    /// Serialize to protocol format
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Calculate nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.name != null) null_bits |= 0x02;
        if (self.icon != null) null_bits |= 0x04;
        if (self.children != null) null_bits |= 0x08;

        // Write nullBits (1 byte)
        try buf.append(allocator, null_bits);

        // Write order (i32 LE)
        try writeI32(&buf, allocator, self.order);

        // Write infoDisplayMode (1 byte)
        try buf.append(allocator, @intFromEnum(self.info_display_mode));

        // Write 4 offset slots (16 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const name_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const icon_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const children_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        // Variable block start position (offset 22)
        const var_block_start = buf.items.len;

        // Write variable fields
        if (self.id) |id_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id_str);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], -1, .little);
        }

        if (self.name) |name_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[name_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, name_str);
        } else {
            std.mem.writeInt(i32, buf.items[name_offset_pos..][0..4], -1, .little);
        }

        if (self.icon) |icon_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[icon_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, icon_str);
        } else {
            std.mem.writeInt(i32, buf.items[icon_offset_pos..][0..4], -1, .little);
        }

        if (self.children) |children_arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[children_offset_pos..][0..4], offset, .little);
            // Write VarInt array length
            try writeVarInt(&buf, allocator, @intCast(children_arr.len));
            // Write each child recursively
            for (children_arr) |*child| {
                const child_data = try child.serialize(allocator);
                defer allocator.free(child_data);
                try buf.appendSlice(allocator, child_data);
            }
        } else {
            std.mem.writeInt(i32, buf.items[children_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Create from JSON (simplified parsing)
    pub fn parseJson(allocator: Allocator, id: []const u8, content: []const u8) !Self {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
            return error.JsonParseError;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidJsonStructure;

        const obj = root.object;

        var asset = Self{
            .id = try allocator.dupe(u8, id),
        };

        // Parse name
        if (obj.get("name")) |name_val| {
            if (name_val == .string) {
                asset.name = try allocator.dupe(u8, name_val.string);
            }
        }

        // Parse icon
        if (obj.get("icon")) |icon_val| {
            if (icon_val == .string) {
                asset.icon = try allocator.dupe(u8, icon_val.string);
            }
        }

        // Parse order
        if (obj.get("order")) |order_val| {
            if (order_val == .integer) {
                asset.order = @intCast(order_val.integer);
            }
        }

        // Note: children parsing would require recursive JSON parsing
        // For now, we don't support nested children from JSON

        return asset;
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.id) |s| allocator.free(s);
        if (self.name) |s| allocator.free(s);
        if (self.icon) |s| allocator.free(s);
        if (self.children) |children_arr| {
            for (children_arr) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children_arr);
        }
    }
};

// Helper functions
fn writeI32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &bytes, value, .little);
    try buf.appendSlice(allocator, &bytes);
}

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

test "ItemCategoryAsset serialization" {
    const allocator = std.testing.allocator;

    var cat = ItemCategoryAsset{
        .id = "weapons",
        .name = "Weapons",
        .icon = "icons/weapons.png",
        .order = 1,
    };

    const data = try cat.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 22 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 22);

    // Check nullBits: id, name, icon set (0x07)
    try std.testing.expectEqual(@as(u8, 0x07), data[0]);

    // Check order at offset 1
    try std.testing.expectEqual(@as(i32, 1), std.mem.readInt(i32, data[1..5], .little));

    // Check infoDisplayMode at offset 5
    try std.testing.expectEqual(@as(u8, 0), data[5]); // tooltip = 0
}
