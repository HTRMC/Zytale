/// CameraShake Asset
///
/// Represents camera shake configuration for first and third person views.
/// Based on com/hypixel/hytale/protocol/CameraShake.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Easing type for animations
pub const EasingType = enum(u8) {
    linear = 0,
    quad_in = 1,
    quad_out = 2,
    quad_in_out = 3,
    cubic_in = 4,
    cubic_out = 5,
    cubic_in_out = 6,
    quart_in = 7,
    quart_out = 8,
    quart_in_out = 9,
    quint_in = 10,
    quint_out = 11,
    quint_in_out = 12,
    sine_in = 13,
    sine_out = 14,
    sine_in_out = 15,
    expo_in = 16,
    expo_out = 17,
    expo_in_out = 18,
    circ_in = 19,
    circ_out = 20,
    circ_in_out = 21,
    elastic_in = 22,
    elastic_out = 23,
    elastic_in_out = 24,
    back_in = 25,
    back_out = 26,
    back_in_out = 27,
    bounce_in = 28,
    bounce_out = 29,
    bounce_in_out = 30,
};

/// Noise type for procedural generation
pub const NoiseType = enum(u8) {
    sin = 0,
    cos = 1,
    perlin_linear = 2,
    perlin_hermite = 3,
    perlin_quintic = 4,
    random = 5,
};

/// Clamp configuration (9 bytes fixed)
pub const ClampConfig = struct {
    min: f32 = 0.0,
    max: f32 = 1.0,
    normalize: bool = false,

    pub fn serialize(self: *const ClampConfig, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.min);
        try writeF32(buf, allocator, self.max);
        try buf.append(allocator, if (self.normalize) 1 else 0);
    }
};

/// Easing configuration (5 bytes fixed)
pub const EasingConfig = struct {
    time: f32 = 0.0,
    easing_type: EasingType = .linear,

    pub fn serialize(self: *const EasingConfig, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.time);
        try buf.append(allocator, @intFromEnum(self.easing_type));
    }
};

/// Noise configuration (23 bytes fixed)
pub const NoiseConfig = struct {
    seed: i32 = 0,
    noise_type: NoiseType = .sin,
    frequency: f32 = 1.0,
    amplitude: f32 = 1.0,
    clamp: ?ClampConfig = null,

    pub fn serialize(self: *const NoiseConfig, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.clamp != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeI32(buf, allocator, self.seed);
        try buf.append(allocator, @intFromEnum(self.noise_type));
        try writeF32(buf, allocator, self.frequency);
        try writeF32(buf, allocator, self.amplitude);

        // Clamp (9 bytes) or zeros
        if (self.clamp) |clamp| {
            try clamp.serialize(buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 9);
        }
    }
};

/// Offset noise (x, y, z arrays of NoiseConfig)
pub const OffsetNoise = struct {
    x: ?[]const NoiseConfig = null,
    y: ?[]const NoiseConfig = null,
    z: ?[]const NoiseConfig = null,

    pub fn serialize(self: *const OffsetNoise, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.x != null) null_bits |= 0x01;
        if (self.y != null) null_bits |= 0x02;
        if (self.z != null) null_bits |= 0x04;
        try buf.append(allocator, null_bits);

        // Offset slots (3 x 4 bytes = 12 bytes)
        const x_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const y_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const z_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        // Write x array
        if (self.x) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[x_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |item| {
                try item.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[x_offset_pos..][0..4], -1, .little);
        }

        // Write y array
        if (self.y) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[y_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |item| {
                try item.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[y_offset_pos..][0..4], -1, .little);
        }

        // Write z array
        if (self.z) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[z_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |item| {
                try item.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[z_offset_pos..][0..4], -1, .little);
        }
    }
};

/// Rotation noise (pitch, yaw, roll arrays of NoiseConfig)
pub const RotationNoise = struct {
    pitch: ?[]const NoiseConfig = null,
    yaw: ?[]const NoiseConfig = null,
    roll: ?[]const NoiseConfig = null,

    pub fn serialize(self: *const RotationNoise, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.pitch != null) null_bits |= 0x01;
        if (self.yaw != null) null_bits |= 0x02;
        if (self.roll != null) null_bits |= 0x04;
        try buf.append(allocator, null_bits);

        // Offset slots (3 x 4 bytes = 12 bytes)
        const pitch_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const yaw_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const roll_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        // Write pitch array
        if (self.pitch) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[pitch_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |item| {
                try item.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[pitch_offset_pos..][0..4], -1, .little);
        }

        // Write yaw array
        if (self.yaw) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[yaw_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |item| {
                try item.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[yaw_offset_pos..][0..4], -1, .little);
        }

        // Write roll array
        if (self.roll) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[roll_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |item| {
                try item.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[roll_offset_pos..][0..4], -1, .little);
        }
    }
};

/// Camera shake configuration
/// Fixed: 1 (nullBits) + 4 (duration) + 4 (startTime) + 1 (continuous) + 5 (easeIn) + 5 (easeOut) + 8 (offsets) = 28 bytes
pub const CameraShakeConfig = struct {
    duration: f32 = 0.0,
    start_time: f32 = 0.0,
    continuous: bool = false,
    ease_in: ?EasingConfig = null,
    ease_out: ?EasingConfig = null,
    offset: ?OffsetNoise = null,
    rotation: ?RotationNoise = null,

    pub fn serialize(self: *const CameraShakeConfig, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.ease_in != null) null_bits |= 0x01;
        if (self.ease_out != null) null_bits |= 0x02;
        if (self.offset != null) null_bits |= 0x04;
        if (self.rotation != null) null_bits |= 0x08;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeF32(buf, allocator, self.duration);
        try writeF32(buf, allocator, self.start_time);
        try buf.append(allocator, if (self.continuous) 1 else 0);

        // easeIn (5 bytes) or zeros
        if (self.ease_in) |*ease| {
            try ease.serialize(buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 5);
        }

        // easeOut (5 bytes) or zeros
        if (self.ease_out) |*ease| {
            try ease.serialize(buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 5);
        }

        // Offset slots (2 x 4 bytes = 8 bytes)
        const offset_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const rotation_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        // Write offset
        if (self.offset) |*ofs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offset_offset_pos..][0..4], offset, .little);
            try ofs.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offset_offset_pos..][0..4], -1, .little);
        }

        // Write rotation
        if (self.rotation) |*rot| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[rotation_offset_pos..][0..4], offset, .little);
            try rot.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[rotation_offset_pos..][0..4], -1, .little);
        }
    }
};

/// CameraShake asset (first and third person configs)
/// Fixed: 1 (nullBits) + 8 (offset slots) = 9 bytes
pub const CameraShakeAsset = struct {
    first_person: ?CameraShakeConfig = null,
    third_person: ?CameraShakeConfig = null,

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
        if (self.first_person != null) null_bits |= 0x01;
        if (self.third_person != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Offset slots (2 x 4 bytes = 8 bytes)
        const first_person_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const third_person_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        // Write firstPerson
        if (self.first_person) |*fp| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[first_person_offset_pos..][0..4], offset, .little);
            try fp.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[first_person_offset_pos..][0..4], -1, .little);
        }

        // Write thirdPerson
        if (self.third_person) |*tp| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[third_person_offset_pos..][0..4], offset, .little);
            try tp.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[third_person_offset_pos..][0..4], -1, .little);
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

fn writeVarInt(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var v: u32 = @bitCast(value);
    while (v >= 0x80) {
        try buf.append(allocator, @truncate((v & 0x7F) | 0x80));
        v >>= 7;
    }
    try buf.append(allocator, @truncate(v));
}

test "CameraShakeAsset empty serialization" {
    const allocator = std.testing.allocator;

    var shake = CameraShakeAsset{};
    const data = try shake.serialize(allocator);
    defer allocator.free(data);

    // Should produce 9 bytes (nullBits + 2 offset slots)
    try std.testing.expectEqual(@as(usize, 9), data.len);

    // Check nullBits is 0
    try std.testing.expectEqual(@as(u8, 0x00), data[0]);
}

test "CameraShakeAsset with first person" {
    const allocator = std.testing.allocator;

    var shake = CameraShakeAsset{
        .first_person = .{
            .duration = 1.0,
            .continuous = true,
        },
    };

    const data = try shake.serialize(allocator);
    defer allocator.free(data);

    // Should have more than 9 bytes
    try std.testing.expect(data.len > 9);

    // Check nullBits has firstPerson
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);
}
