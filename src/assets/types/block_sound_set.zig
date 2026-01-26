/// BlockSoundSet Asset
///
/// Represents a set of sounds for block interactions.
/// Based on com/hypixel/hytale/protocol/BlockSoundSet.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Block sound event types
pub const BlockSoundEvent = enum(u8) {
    walk = 0,
    land = 1,
    move_in = 2,
    move_out = 3,
    hit = 4,
    break_block = 5,
    build = 6,
    clone = 7,
    harvest = 8,
};

/// Float range (8 bytes fixed)
pub const FloatRange = struct {
    inclusive_min: f32 = 0.0,
    inclusive_max: f32 = 1.0,

    pub fn serialize(self: *const FloatRange, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.inclusive_min);
        try writeF32(buf, allocator, self.inclusive_max);
    }
};

/// Sound event entry (maps BlockSoundEvent -> sound event index)
pub const SoundEventIndexEntry = struct {
    event: BlockSoundEvent,
    index: i32,
};

/// BlockSoundSet asset
/// Fixed: 1 (nullBits) + 8 (moveInRepeatRange) + 8 (offset slots) = 17 bytes
pub const BlockSoundSetAsset = struct {
    id: ?[]const u8 = null,
    sound_event_indices: ?[]const SoundEventIndexEntry = null,
    move_in_repeat_range: ?FloatRange = null,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 9;
    pub const VARIABLE_FIELD_COUNT: u32 = 2;
    pub const VARIABLE_BLOCK_START: u32 = 17;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.move_in_repeat_range != null) null_bits |= 0x01;
        if (self.id != null) null_bits |= 0x02;
        if (self.sound_event_indices != null) null_bits |= 0x04;
        try buf.append(allocator, null_bits);

        // moveInRepeatRange (8 bytes) or zeros
        if (self.move_in_repeat_range) |*range| {
            try range.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 8);
        }

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

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
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

test "BlockSoundSetAsset serialization" {
    const allocator = std.testing.allocator;

    var sound_set = BlockSoundSetAsset{
        .id = "grass_sounds",
    };

    const data = try sound_set.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 17 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 17);

    // Check nullBits: id set (0x02)
    try std.testing.expectEqual(@as(u8, 0x02), data[0]);
}

test "BlockSoundSetAsset with sound events" {
    const allocator = std.testing.allocator;

    const indices = [_]SoundEventIndexEntry{
        .{ .event = .walk, .index = 0 },
        .{ .event = .land, .index = 1 },
    };

    var sound_set = BlockSoundSetAsset{
        .id = "stone_sounds",
        .sound_event_indices = &indices,
        .move_in_repeat_range = .{ .inclusive_min = 0.1, .inclusive_max = 0.5 },
    };

    const data = try sound_set.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: moveInRepeatRange (0x01) + id (0x02) + soundEventIndices (0x04) = 0x07
    try std.testing.expectEqual(@as(u8, 0x07), data[0]);
}
