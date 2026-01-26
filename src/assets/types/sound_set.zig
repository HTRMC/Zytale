/// SoundSet Asset
///
/// Represents a collection of sounds mapped by string keys.
/// Based on com/hypixel/hytale/protocol/SoundSet.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Sound category for audio grouping
pub const SoundCategory = enum(u8) {
    music = 0,
    ambient = 1,
    sfx = 2,
    ui = 3,

    pub fn fromValue(value: u8) SoundCategory {
        return @enumFromInt(value);
    }
};

/// Sound entry (string key -> sound event index)
pub const SoundEntry = struct {
    key: []const u8,
    value: i32,
};

/// SoundSet asset
pub const SoundSetAsset = struct {
    id: ?[]const u8 = null,
    sounds: ?[]const SoundEntry = null,
    category: SoundCategory = .music,

    const Self = @This();

    /// Protocol constants from Java
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 2;
    pub const VARIABLE_FIELD_COUNT: u32 = 2;
    pub const VARIABLE_BLOCK_START: u32 = 10;

    /// Serialize to protocol format
    /// Format:
    /// - nullBits (1 byte): bit 0 = id present, bit 1 = sounds present
    /// - category (1 byte): SoundCategory enum
    /// - idOffset (4 bytes LE): offset to id string
    /// - soundsOffset (4 bytes LE): offset to sounds dictionary
    /// - Variable: id string, sounds dict
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Calculate nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.sounds != null) null_bits |= 0x02;

        // Write nullBits (1 byte)
        try buf.append(allocator, null_bits);

        // Write category (1 byte)
        try buf.append(allocator, @intFromEnum(self.category));

        // Write 2 offset slots (8 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const sounds_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        // Variable block start position (offset 10)
        const var_block_start = buf.items.len;

        // Write id string
        if (self.id) |id_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id_str);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], -1, .little);
        }

        // Write sounds dictionary
        if (self.sounds) |sounds| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sounds_offset_pos..][0..4], offset, .little);

            // VarInt count
            try writeVarInt(&buf, allocator, @intCast(sounds.len));

            // Each entry: VarString key + i32 value
            for (sounds) |entry| {
                try writeVarString(&buf, allocator, entry.key);
                try writeI32(&buf, allocator, entry.value);
            }
        } else {
            std.mem.writeInt(i32, buf.items[sounds_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.id) |s| allocator.free(s);
        if (self.sounds) |sounds| {
            for (sounds) |entry| {
                allocator.free(entry.key);
            }
            allocator.free(sounds);
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

test "SoundSetAsset serialization" {
    const allocator = std.testing.allocator;

    var sound_set = SoundSetAsset{
        .id = "test_sounds",
        .category = .sfx,
    };

    const data = try sound_set.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 10 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 10);

    // Check nullBits: id set (0x01)
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);

    // Check category is sfx (2)
    try std.testing.expectEqual(@as(u8, 2), data[1]);
}

test "SoundSetAsset with sounds" {
    const allocator = std.testing.allocator;

    const sounds = [_]SoundEntry{
        .{ .key = "hit", .value = 1 },
        .{ .key = "miss", .value = 2 },
    };

    var sound_set = SoundSetAsset{
        .id = "combat",
        .sounds = &sounds,
        .category = .sfx,
    };

    const data = try sound_set.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: id (0x01) + sounds (0x02) = 0x03
    try std.testing.expectEqual(@as(u8, 0x03), data[0]);
}
