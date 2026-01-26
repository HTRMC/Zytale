/// SoundEvent Asset
///
/// Represents a sound event with layers and configuration.
/// Based on com/hypixel/hytale/protocol/SoundEvent.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Random settings for sound event layer (20 bytes fixed)
pub const SoundEventLayerRandomSettings = struct {
    min_volume: f32 = 0.0,
    max_volume: f32 = 1.0,
    min_pitch: f32 = 1.0,
    max_pitch: f32 = 1.0,
    max_start_offset: f32 = 0.0,

    pub fn serialize(self: *const SoundEventLayerRandomSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.min_volume);
        try writeF32(buf, allocator, self.max_volume);
        try writeF32(buf, allocator, self.min_pitch);
        try writeF32(buf, allocator, self.max_pitch);
        try writeF32(buf, allocator, self.max_start_offset);
    }
};

/// Sound event layer (42 bytes fixed + variable files array)
pub const SoundEventLayer = struct {
    volume: f32 = 1.0,
    start_delay: f32 = 0.0,
    looping: bool = false,
    probability: i32 = 100,
    probability_reroll_delay: f32 = 0.0,
    round_robin_history_size: i32 = 0,
    random_settings: ?SoundEventLayerRandomSettings = null,
    files: ?[]const []const u8 = null,

    pub fn serialize(self: *const SoundEventLayer, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.random_settings != null) null_bits |= 0x01;
        if (self.files != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeF32(buf, allocator, self.volume);
        try writeF32(buf, allocator, self.start_delay);
        try buf.append(allocator, if (self.looping) 1 else 0);
        try writeI32(buf, allocator, self.probability);
        try writeF32(buf, allocator, self.probability_reroll_delay);
        try writeI32(buf, allocator, self.round_robin_history_size);

        // randomSettings (20 bytes) or zeros
        if (self.random_settings) |*settings| {
            try settings.serialize(buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 20);
        }

        // files array (variable, inline)
        if (self.files) |files| {
            try writeVarInt(buf, allocator, @intCast(files.len));
            for (files) |file| {
                try writeVarString(buf, allocator, file);
            }
        }
    }
};

/// SoundEvent asset
/// Fixed: 1 (nullBits) + 4 (volume) + 4 (pitch) + 4 (musicDuckingVolume) + 4 (ambientDuckingVolume)
///      + 4 (maxInstance) + 1 (preventSoundInterruption) + 4 (startAttenuationDistance) + 4 (maxDistance)
///      + 4 (audioCategory) + 8 (offset slots) = 42 bytes
pub const SoundEventAsset = struct {
    id: ?[]const u8 = null,
    volume: f32 = 1.0,
    pitch: f32 = 1.0,
    music_ducking_volume: f32 = 1.0,
    ambient_ducking_volume: f32 = 1.0,
    max_instance: i32 = 1,
    prevent_sound_interruption: bool = false,
    start_attenuation_distance: f32 = 0.0,
    max_distance: f32 = 100.0,
    layers: ?[]const SoundEventLayer = null,
    audio_category: i32 = 0,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 34;
    pub const VARIABLE_FIELD_COUNT: u32 = 2;
    pub const VARIABLE_BLOCK_START: u32 = 42;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.layers != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeF32(&buf, allocator, self.volume);
        try writeF32(&buf, allocator, self.pitch);
        try writeF32(&buf, allocator, self.music_ducking_volume);
        try writeF32(&buf, allocator, self.ambient_ducking_volume);
        try writeI32(&buf, allocator, self.max_instance);
        try buf.append(allocator, if (self.prevent_sound_interruption) 1 else 0);
        try writeF32(&buf, allocator, self.start_attenuation_distance);
        try writeF32(&buf, allocator, self.max_distance);
        try writeI32(&buf, allocator, self.audio_category);

        // Offset slots (2 x 4 bytes = 8 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const layers_offset_pos = buf.items.len;
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

        // Write layers array
        if (self.layers) |layers| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[layers_offset_pos..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(layers.len));
            for (layers) |*layer| {
                try layer.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[layers_offset_pos..][0..4], -1, .little);
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

test "SoundEventAsset serialization" {
    const allocator = std.testing.allocator;

    var event = SoundEventAsset{
        .id = "footstep",
        .volume = 0.8,
        .audio_category = 2,
    };

    const data = try event.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 42 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 42);

    // Check nullBits: id set (0x01)
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);
}

test "SoundEventAsset with layers" {
    const allocator = std.testing.allocator;

    const files = [_][]const u8{ "sound1.ogg", "sound2.ogg" };
    const layers = [_]SoundEventLayer{
        .{ .volume = 1.0, .files = &files },
    };

    var event = SoundEventAsset{
        .id = "explosion",
        .layers = &layers,
    };

    const data = try event.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: id (0x01) + layers (0x02) = 0x03
    try std.testing.expectEqual(@as(u8, 0x03), data[0]);
}
