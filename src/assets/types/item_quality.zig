/// ItemQuality Asset
///
/// Represents item quality/rarity (common, rare, legendary, etc.)
/// Based on com/hypixel/hytale/protocol/ItemQuality.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Color (RGB)
pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    pub fn serialize(self: *const Color, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.r);
        try buf.append(allocator, self.g);
        try buf.append(allocator, self.b);
    }
};

/// ItemQuality asset
pub const ItemQualityAsset = struct {
    id: ?[]const u8 = null,
    item_tooltip_texture: ?[]const u8 = null,
    item_tooltip_arrow_texture: ?[]const u8 = null,
    slot_texture: ?[]const u8 = null,
    block_slot_texture: ?[]const u8 = null,
    special_slot_texture: ?[]const u8 = null,
    text_color: ?Color = null,
    localization_key: ?[]const u8 = null,
    visible_quality_label: bool = false,
    render_special_slot: bool = false,
    hide_from_search: bool = false,

    const Self = @This();

    /// Protocol constants from Java
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 7;
    pub const VARIABLE_FIELD_COUNT: u32 = 7;
    pub const VARIABLE_BLOCK_START: u32 = 35;

    /// Serialize to protocol format
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Calculate nullBits
        var null_bits: u8 = 0;
        if (self.text_color != null) null_bits |= 0x01;
        if (self.id != null) null_bits |= 0x02;
        if (self.item_tooltip_texture != null) null_bits |= 0x04;
        if (self.item_tooltip_arrow_texture != null) null_bits |= 0x08;
        if (self.slot_texture != null) null_bits |= 0x10;
        if (self.block_slot_texture != null) null_bits |= 0x20;
        if (self.special_slot_texture != null) null_bits |= 0x40;
        if (self.localization_key != null) null_bits |= 0x80;

        // Write nullBits (1 byte)
        try buf.append(allocator, null_bits);

        // Write textColor (3 bytes) or zeros
        if (self.text_color) |color| {
            try color.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 3);
        }

        // Write bools
        try buf.append(allocator, if (self.visible_quality_label) 1 else 0);
        try buf.append(allocator, if (self.render_special_slot) 1 else 0);
        try buf.append(allocator, if (self.hide_from_search) 1 else 0);

        // Write 7 offset slots (28 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const tooltip_tex_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const tooltip_arrow_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const slot_tex_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const block_slot_tex_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const special_slot_tex_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const loc_key_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        // Variable block start position (offset 35)
        const var_block_start = buf.items.len;

        // Write variable fields
        if (self.id) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], -1, .little);
        }

        if (self.item_tooltip_texture) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[tooltip_tex_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[tooltip_tex_offset_pos..][0..4], -1, .little);
        }

        if (self.item_tooltip_arrow_texture) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[tooltip_arrow_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[tooltip_arrow_offset_pos..][0..4], -1, .little);
        }

        if (self.slot_texture) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[slot_tex_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[slot_tex_offset_pos..][0..4], -1, .little);
        }

        if (self.block_slot_texture) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[block_slot_tex_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[block_slot_tex_offset_pos..][0..4], -1, .little);
        }

        if (self.special_slot_texture) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[special_slot_tex_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[special_slot_tex_offset_pos..][0..4], -1, .little);
        }

        if (self.localization_key) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[loc_key_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[loc_key_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.id) |s| allocator.free(s);
        if (self.item_tooltip_texture) |s| allocator.free(s);
        if (self.item_tooltip_arrow_texture) |s| allocator.free(s);
        if (self.slot_texture) |s| allocator.free(s);
        if (self.block_slot_texture) |s| allocator.free(s);
        if (self.special_slot_texture) |s| allocator.free(s);
        if (self.localization_key) |s| allocator.free(s);
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

test "ItemQualityAsset serialization" {
    const allocator = std.testing.allocator;

    var quality = ItemQualityAsset{
        .id = "common",
        .text_color = .{ .r = 255, .g = 255, .b = 255 },
        .visible_quality_label = true,
    };

    const data = try quality.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 35 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 35);

    // Check nullBits: textColor (0x01) + id (0x02) = 0x03
    try std.testing.expectEqual(@as(u8, 0x03), data[0]);
}
