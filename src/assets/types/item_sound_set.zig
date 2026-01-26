/// ItemSoundSet Asset
///
/// Represents a set of sounds for item interactions (drag/drop).
/// Based on com/hypixel/hytale/protocol/ItemSoundSet.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Item sound event types
pub const ItemSoundEvent = enum(u8) {
    drag = 0,
    drop = 1,
};

/// Sound event entry (maps ItemSoundEvent -> sound event index)
pub const ItemSoundEventEntry = struct {
    event: ItemSoundEvent,
    index: i32,
};

/// ItemSoundSet asset
/// Fixed: 1 (nullBits) + 8 (offset slots) = 9 bytes
pub const ItemSoundSetAsset = struct {
    id: ?[]const u8 = null,
    sound_event_indices: ?[]const ItemSoundEventEntry = null,

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
        if (self.sound_event_indices != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Offset slots (2 x 4 bytes = 8 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const sound_event_indices_offset_pos = buf.items.len;
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

        // Write soundEventIndices dictionary
        if (self.sound_event_indices) |indices| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sound_event_indices_offset_pos..][0..4], offset, .little);

            // VarInt count
            try writeVarInt(&buf, allocator, @intCast(indices.len));

            // Each entry: u8 key + i32 value
            for (indices) |entry| {
                try buf.append(allocator, @intFromEnum(entry.event));
                try writeI32(&buf, allocator, entry.index);
            }
        } else {
            std.mem.writeInt(i32, buf.items[sound_event_indices_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
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

test "ItemSoundSetAsset serialization" {
    const allocator = std.testing.allocator;

    var sound_set = ItemSoundSetAsset{
        .id = "default_item_sounds",
    };

    const data = try sound_set.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 9 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 9);

    // Check nullBits: id set (0x01)
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);
}

test "ItemSoundSetAsset with sound events" {
    const allocator = std.testing.allocator;

    const indices = [_]ItemSoundEventEntry{
        .{ .event = .drag, .index = 0 },
        .{ .event = .drop, .index = 1 },
    };

    var sound_set = ItemSoundSetAsset{
        .id = "weapon_sounds",
        .sound_event_indices = &indices,
    };

    const data = try sound_set.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: id (0x01) + soundEventIndices (0x02) = 0x03
    try std.testing.expectEqual(@as(u8, 0x03), data[0]);
}
