/// AmbienceFX Asset Type
///
/// Represents ambient sound effects, music, and conditions.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Sound play mode
pub const AmbienceFXSoundPlay3D = enum(u8) {
    random = 0,
    location_name = 1,
    no = 2,
};

/// Altitude mode
pub const AmbienceFXAltitude = enum(u8) {
    normal = 0,
    lowest = 1,
    highest = 2,
    random = 3,
};

/// Transition speed
pub const AmbienceTransitionSpeed = enum(u8) {
    default = 0,
    fast = 1,
    instant = 2,
};

/// Integer range (8 bytes)
pub const Range = struct {
    min: i32 = 0,
    max: i32 = 0,

    pub fn serialize(self: Range, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(i32, bytes[0..4], self.min, .little);
        std.mem.writeInt(i32, bytes[4..8], self.max, .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// Byte range (2 bytes)
pub const Rangeb = struct {
    min: u8 = 0,
    max: u8 = 0,

    pub fn serialize(self: Rangeb, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.min);
        try buf.append(allocator, self.max);
    }
};

/// Float range (8 bytes)
pub const Rangef = struct {
    min: f32 = 0.0,
    max: f32 = 0.0,

    pub fn serialize(self: Rangef, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], @bitCast(self.min), .little);
        std.mem.writeInt(u32, bytes[4..8], @bitCast(self.max), .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// Sound effect settings (9 bytes)
pub const AmbienceFXSoundEffect = struct {
    reverb_effect_index: i32 = 0,
    equalizer_effect_index: i32 = 0,
    is_instant: bool = false,

    pub const SIZE: usize = 9;

    pub fn serialize(self: AmbienceFXSoundEffect, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var reverb_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &reverb_bytes, self.reverb_effect_index, .little);
        try buf.appendSlice(allocator, &reverb_bytes);

        var eq_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &eq_bytes, self.equalizer_effect_index, .little);
        try buf.appendSlice(allocator, &eq_bytes);

        try buf.append(allocator, if (self.is_instant) @as(u8, 1) else 0);
    }
};

/// Block sound set condition (13 bytes)
pub const AmbienceFXBlockSoundSet = struct {
    block_sound_set_index: i32 = 0,
    percent: ?Rangef = null,

    pub const SIZE: usize = 13;

    pub fn serialize(self: AmbienceFXBlockSoundSet, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.percent != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // blockSoundSetIndex
        var idx_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &idx_bytes, self.block_sound_set_index, .little);
        try buf.appendSlice(allocator, &idx_bytes);

        // percent (8 bytes, always written)
        if (self.percent) |p| {
            try p.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }
    }
};

/// Ambient sound (27 bytes)
pub const AmbienceFXSound = struct {
    sound_event_index: i32 = 0,
    play_3d: AmbienceFXSoundPlay3D = .random,
    block_sound_set_index: i32 = 0,
    altitude: AmbienceFXAltitude = .normal,
    frequency: ?Rangef = null,
    radius: ?Range = null,

    pub const SIZE: usize = 27;

    pub fn serialize(self: AmbienceFXSound, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.frequency != null) null_bits |= 0x01;
        if (self.radius != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // soundEventIndex
        var sei_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &sei_bytes, self.sound_event_index, .little);
        try buf.appendSlice(allocator, &sei_bytes);

        // play3D
        try buf.append(allocator, @intFromEnum(self.play_3d));

        // blockSoundSetIndex
        var bssi_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &bssi_bytes, self.block_sound_set_index, .little);
        try buf.appendSlice(allocator, &bssi_bytes);

        // altitude
        try buf.append(allocator, @intFromEnum(self.altitude));

        // frequency (8 bytes, always written)
        if (self.frequency) |f| {
            try f.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // radius (8 bytes, always written)
        if (self.radius) |r| {
            try r.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }
    }
};

/// Music settings (5 bytes fixed + inline variable string array)
pub const AmbienceFXMusic = struct {
    tracks: ?[]const []const u8 = null,
    volume: f32 = 0.0,

    pub fn serialize(self: AmbienceFXMusic, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.tracks != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // volume
        try writeF32(buf, allocator, self.volume);

        // tracks (inline variable array)
        if (self.tracks) |tracks| {
            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(tracks.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (tracks) |track| {
                try writeVarString(buf, allocator, track);
            }
        }
    }
};

/// Ambient bed settings (6 bytes fixed + inline variable string)
pub const AmbienceFXAmbientBed = struct {
    track: ?[]const u8 = null,
    volume: f32 = 0.0,
    transition_speed: AmbienceTransitionSpeed = .default,

    pub fn serialize(self: AmbienceFXAmbientBed, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.track != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // volume
        try writeF32(buf, allocator, self.volume);

        // transitionSpeed
        try buf.append(allocator, @intFromEnum(self.transition_speed));

        // track (inline variable string)
        if (self.track) |t| {
            try writeVarString(buf, allocator, t);
        }
    }
};

/// Ambient conditions (57 bytes fixed + offset-based variable)
pub const AmbienceFXConditions = struct {
    never: bool = false,
    environment_indices: ?[]const i32 = null,
    weather_indices: ?[]const i32 = null,
    fluid_fx_indices: ?[]const i32 = null,
    environment_tag_pattern_index: i32 = 0,
    weather_tag_pattern_index: i32 = 0,
    surrounding_block_sound_sets: ?[]const AmbienceFXBlockSoundSet = null,
    altitude: ?Range = null,
    walls: ?Rangeb = null,
    roof: bool = false,
    roof_material_tag_pattern_index: i32 = 0,
    floor: bool = false,
    sun_light_level: ?Rangeb = null,
    torch_light_level: ?Rangeb = null,
    global_light_level: ?Rangeb = null,
    day_time: ?Rangef = null,

    pub const FIXED_BLOCK_SIZE: u32 = 41;
    pub const VARIABLE_BLOCK_START: u32 = 57;

    pub fn serialize(self: AmbienceFXConditions, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits (2 bytes)
        var null_bits: [2]u8 = .{ 0, 0 };
        if (self.altitude != null) null_bits[0] |= 0x01;
        if (self.walls != null) null_bits[0] |= 0x02;
        if (self.sun_light_level != null) null_bits[0] |= 0x04;
        if (self.torch_light_level != null) null_bits[0] |= 0x08;
        if (self.global_light_level != null) null_bits[0] |= 0x10;
        if (self.day_time != null) null_bits[0] |= 0x20;
        if (self.environment_indices != null) null_bits[0] |= 0x40;
        if (self.weather_indices != null) null_bits[0] |= 0x80;
        if (self.fluid_fx_indices != null) null_bits[1] |= 0x01;
        if (self.surrounding_block_sound_sets != null) null_bits[1] |= 0x02;
        try buf.appendSlice(allocator, &null_bits);

        // never
        try buf.append(allocator, if (self.never) @as(u8, 1) else 0);

        // environmentTagPatternIndex
        try writeI32(buf, allocator, self.environment_tag_pattern_index);

        // weatherTagPatternIndex
        try writeI32(buf, allocator, self.weather_tag_pattern_index);

        // altitude (8 bytes, always written)
        if (self.altitude) |a| {
            try a.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // walls (2 bytes, always written)
        if (self.walls) |w| {
            try w.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0 });
        }

        // roof
        try buf.append(allocator, if (self.roof) @as(u8, 1) else 0);

        // roofMaterialTagPatternIndex
        try writeI32(buf, allocator, self.roof_material_tag_pattern_index);

        // floor
        try buf.append(allocator, if (self.floor) @as(u8, 1) else 0);

        // sunLightLevel (2 bytes, always written)
        if (self.sun_light_level) |s| {
            try s.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0 });
        }

        // torchLightLevel (2 bytes, always written)
        if (self.torch_light_level) |t| {
            try t.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0 });
        }

        // globalLightLevel (2 bytes, always written)
        if (self.global_light_level) |g| {
            try g.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0 });
        }

        // dayTime (8 bytes, always written)
        if (self.day_time) |d| {
            try d.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // Reserve 4 offset slots (16 bytes)
        const env_indices_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const weather_indices_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const fluid_fx_indices_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const block_sound_sets_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // environmentIndices
        if (self.environment_indices) |indices| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[env_indices_offset_slot..][0..4], offset, .little);
            try writeI32Array(buf, allocator, indices);
        } else {
            std.mem.writeInt(i32, buf.items[env_indices_offset_slot..][0..4], -1, .little);
        }

        // weatherIndices
        if (self.weather_indices) |indices| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[weather_indices_offset_slot..][0..4], offset, .little);
            try writeI32Array(buf, allocator, indices);
        } else {
            std.mem.writeInt(i32, buf.items[weather_indices_offset_slot..][0..4], -1, .little);
        }

        // fluidFXIndices
        if (self.fluid_fx_indices) |indices| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[fluid_fx_indices_offset_slot..][0..4], offset, .little);
            try writeI32Array(buf, allocator, indices);
        } else {
            std.mem.writeInt(i32, buf.items[fluid_fx_indices_offset_slot..][0..4], -1, .little);
        }

        // surroundingBlockSoundSets
        if (self.surrounding_block_sound_sets) |sets| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[block_sound_sets_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(sets.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (sets) |s| {
                try s.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[block_sound_sets_offset_slot..][0..4], -1, .little);
        }
    }
};

/// AmbienceFX asset (42 bytes fixed + variable)
pub const AmbienceFXAsset = struct {
    id: ?[]const u8 = null,
    conditions: ?AmbienceFXConditions = null,
    sounds: ?[]const AmbienceFXSound = null,
    music: ?AmbienceFXMusic = null,
    ambient_bed: ?AmbienceFXAmbientBed = null,
    sound_effect: ?AmbienceFXSoundEffect = null,
    priority: i32 = 0,
    blocked_ambience_fx_indices: ?[]const i32 = null,
    audio_category_index: i32 = 0,

    const Self = @This();

    pub const FIXED_BLOCK_SIZE: u32 = 18;
    pub const VARIABLE_BLOCK_START: u32 = 42;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.sound_effect != null) null_bits |= 0x01;
        if (self.id != null) null_bits |= 0x02;
        if (self.conditions != null) null_bits |= 0x04;
        if (self.sounds != null) null_bits |= 0x08;
        if (self.music != null) null_bits |= 0x10;
        if (self.ambient_bed != null) null_bits |= 0x20;
        if (self.blocked_ambience_fx_indices != null) null_bits |= 0x40;
        try buf.append(allocator, null_bits);

        // soundEffect (9 bytes, always written)
        if (self.sound_effect) |se| {
            try se.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 9);
        }

        // priority
        try writeI32(&buf, allocator, self.priority);

        // audioCategoryIndex
        try writeI32(&buf, allocator, self.audio_category_index);

        // Reserve 6 offset slots (24 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const conditions_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const sounds_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const music_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const ambient_bed_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const blocked_indices_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // id
        if (self.id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], -1, .little);
        }

        // conditions
        if (self.conditions) |c| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[conditions_offset_slot..][0..4], offset, .little);
            try c.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[conditions_offset_slot..][0..4], -1, .little);
        }

        // sounds
        if (self.sounds) |sounds| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sounds_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(sounds.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (sounds) |s| {
                try s.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[sounds_offset_slot..][0..4], -1, .little);
        }

        // music
        if (self.music) |m| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[music_offset_slot..][0..4], offset, .little);
            try m.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[music_offset_slot..][0..4], -1, .little);
        }

        // ambientBed
        if (self.ambient_bed) |ab| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[ambient_bed_offset_slot..][0..4], offset, .little);
            try ab.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[ambient_bed_offset_slot..][0..4], -1, .little);
        }

        // blockedAmbienceFxIndices
        if (self.blocked_ambience_fx_indices) |indices| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[blocked_indices_offset_slot..][0..4], offset, .little);
            try writeI32Array(&buf, allocator, indices);
        } else {
            std.mem.writeInt(i32, buf.items[blocked_indices_offset_slot..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }
};

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeI32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &bytes, value, .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeVarIntBuf(buf: *[5]u8, value: i32) usize {
    var v: u32 = @bitCast(value);
    var i: usize = 0;
    while (v >= 0x80) {
        buf[i] = @truncate((v & 0x7F) | 0x80);
        v >>= 7;
        i += 1;
    }
    buf[i] = @truncate(v);
    return i + 1;
}

fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(str.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);
    try buf.appendSlice(allocator, str);
}

fn writeI32Array(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, arr: []const i32) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(arr.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);

    for (arr) |v| {
        try writeI32(buf, allocator, v);
    }
}

test "AmbienceFXAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = AmbienceFXAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 42 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 42), data.len);

    // Check nullBits is 0 (nothing set)
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check offset slots are -1
    const id_offset = std.mem.readInt(i32, data[18..22], .little);
    try std.testing.expectEqual(@as(i32, -1), id_offset);
}

test "AmbienceFXAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = AmbienceFXAsset{
        .id = "forest_ambient",
        .priority = 10,
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed (42) + VarInt(14) + "forest_ambient"
    try std.testing.expectEqual(@as(usize, 42 + 1 + 14), data.len);

    // Check nullBits has id set
    try std.testing.expectEqual(@as(u8, 0x02), data[0]);

    // Check id offset is 0
    const id_offset = std.mem.readInt(i32, data[18..22], .little);
    try std.testing.expectEqual(@as(i32, 0), id_offset);
}

test "AmbienceFXSound serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const sound = AmbienceFXSound{ .sound_event_index = 1 };
    try sound.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 27), buf.items.len);
}
