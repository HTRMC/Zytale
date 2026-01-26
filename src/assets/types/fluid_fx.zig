/// FluidFX Asset Type
///
/// Represents fluid visual effects including fog, color filtering, particles,
/// and movement settings for fluids like water and lava.

const std = @import("std");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;

/// Shader type for fluid rendering
pub const ShaderType = enum(u8) {
    none = 0,
    wind = 1,
    wind_attached = 2,
    wind_random = 3,
    wind_fractal = 4,
    ice = 5,
    water = 6,
    lava = 7,
    slime = 8,
    ripple = 9,
};

/// Fog mode for fluid rendering
pub const FluidFog = enum(u8) {
    color = 0,
    color_light = 1,
    environment_tint = 2,
};

/// Near/far distance pair (8 bytes)
pub const NearFar = struct {
    near: f32 = 0.0,
    far: f32 = 0.0,

    pub fn serialize(self: NearFar, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], @bitCast(self.near), .little);
        std.mem.writeInt(u32, bytes[4..8], @bitCast(self.far), .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// Movement settings for fluids (24 bytes fixed)
pub const FluidFXMovementSettings = struct {
    swim_up_speed: f32 = 0.0,
    swim_down_speed: f32 = 0.0,
    sink_speed: f32 = 0.0,
    horizontal_speed_multiplier: f32 = 1.0,
    field_of_view_multiplier: f32 = 1.0,
    entry_velocity_multiplier: f32 = 1.0,

    pub fn serialize(self: FluidFXMovementSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [24]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], @bitCast(self.swim_up_speed), .little);
        std.mem.writeInt(u32, bytes[4..8], @bitCast(self.swim_down_speed), .little);
        std.mem.writeInt(u32, bytes[8..12], @bitCast(self.sink_speed), .little);
        std.mem.writeInt(u32, bytes[12..16], @bitCast(self.horizontal_speed_multiplier), .little);
        std.mem.writeInt(u32, bytes[16..20], @bitCast(self.field_of_view_multiplier), .little);
        std.mem.writeInt(u32, bytes[20..24], @bitCast(self.entry_velocity_multiplier), .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// Fluid particle effect
pub const FluidParticle = struct {
    system_id: ?[]const u8 = null,
    color: ?common.Color = null,
    scale: f32 = 1.0,

    /// Serialize FluidParticle (inline variable format)
    /// Format: nullBits(1) + color(3) + scale(4) + [VarString systemId]
    pub fn serialize(self: FluidParticle, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.color != null) null_bits |= 0x01;
        if (self.system_id != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // color (3 bytes, always written even if null)
        if (self.color) |c| {
            try buf.appendSlice(allocator, &[_]u8{ c.r, c.g, c.b });
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // scale (f32 LE)
        var scale_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &scale_bytes, @bitCast(self.scale), .little);
        try buf.appendSlice(allocator, &scale_bytes);

        // systemId (VarString, inline)
        if (self.system_id) |id| {
            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, id);
        }
    }

    pub fn computeSize(self: FluidParticle) usize {
        var size: usize = 8; // nullBits + color + scale
        if (self.system_id) |id| {
            size += varIntSize(@intCast(id.len)) + id.len;
        }
        return size;
    }
};

/// FluidFX asset
pub const FluidFXAsset = struct {
    /// Asset ID
    id: ?[]const u8 = null,

    /// Shader type for fluid rendering
    shader: ShaderType = .none,

    /// Fog mode
    fog_mode: FluidFog = .color,

    /// Fog color (nullable)
    fog_color: ?common.Color = null,

    /// Fog distance near/far (nullable)
    fog_distance: ?NearFar = null,

    /// Fog depth start
    fog_depth_start: f32 = 0.0,

    /// Fog depth falloff
    fog_depth_falloff: f32 = 0.0,

    /// Color filter (nullable)
    color_filter: ?common.Color = null,

    /// Color saturation
    color_saturation: f32 = 1.0,

    /// Distortion amplitude
    distortion_amplitude: f32 = 0.0,

    /// Distortion frequency
    distortion_frequency: f32 = 0.0,

    /// Movement settings (nullable)
    movement_settings: ?FluidFXMovementSettings = null,

    /// Particle effect (nullable)
    particle: ?FluidParticle = null,

    const Self = @This();

    /// Protocol serialization constants
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 61;
    pub const VARIABLE_FIELD_COUNT: u32 = 2;
    pub const VARIABLE_BLOCK_START: u32 = 69;

    /// Serialize to protocol format
    /// Format: nullBits(1) + shader(1) + fogMode(1) + fogColor(3) + fogDistance(8) +
    ///         fogDepthStart(4) + fogDepthFalloff(4) + colorFilter(3) + colorSaturation(4) +
    ///         distortionAmplitude(4) + distortionFrequency(4) + movementSettings(24) +
    ///         idOffset(4) + particleOffset(4) + [variable: id, particle]
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.fog_color != null) null_bits |= 0x01;
        if (self.fog_distance != null) null_bits |= 0x02;
        if (self.color_filter != null) null_bits |= 0x04;
        if (self.movement_settings != null) null_bits |= 0x08;
        if (self.id != null) null_bits |= 0x10;
        if (self.particle != null) null_bits |= 0x20;
        try buf.append(allocator, null_bits);

        // shader (1 byte)
        try buf.append(allocator, @intFromEnum(self.shader));

        // fogMode (1 byte)
        try buf.append(allocator, @intFromEnum(self.fog_mode));

        // fogColor (3 bytes, always written)
        if (self.fog_color) |c| {
            try buf.appendSlice(allocator, &[_]u8{ c.r, c.g, c.b });
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // fogDistance (8 bytes, always written)
        if (self.fog_distance) |fd| {
            try fd.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 });
        }

        // fogDepthStart (f32 LE)
        try writeF32(&buf, allocator, self.fog_depth_start);

        // fogDepthFalloff (f32 LE)
        try writeF32(&buf, allocator, self.fog_depth_falloff);

        // colorFilter (3 bytes, always written)
        if (self.color_filter) |c| {
            try buf.appendSlice(allocator, &[_]u8{ c.r, c.g, c.b });
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // colorSaturation (f32 LE)
        try writeF32(&buf, allocator, self.color_saturation);

        // distortionAmplitude (f32 LE)
        try writeF32(&buf, allocator, self.distortion_amplitude);

        // distortionFrequency (f32 LE)
        try writeF32(&buf, allocator, self.distortion_frequency);

        // movementSettings (24 bytes, always written)
        if (self.movement_settings) |ms| {
            try ms.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 24);
        }

        // Reserve offset slots (8 bytes total)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 }); // idOffset

        const particle_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 }); // particleOffset

        // Variable block starts here (position 69)
        const var_block_start = buf.items.len;

        // id string (if present)
        if (self.id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], -1, .little);
        }

        // particle (if present)
        if (self.particle) |p| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[particle_offset_slot..][0..4], offset, .little);
            try p.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[particle_offset_slot..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.id) |id| allocator.free(id);
        if (self.particle) |*p| {
            if (p.system_id) |sid| allocator.free(sid);
        }
    }
};

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
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

fn varIntSize(value: i32) usize {
    var v: u32 = @bitCast(value);
    var size: usize = 1;
    while (v >= 0x80) {
        v >>= 7;
        size += 1;
    }
    return size;
}

test "FluidFXAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = FluidFXAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 69 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 69), data.len);

    // Check nullBits is 0 (nothing set)
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check shader and fogMode are defaults
    try std.testing.expectEqual(@as(u8, 0), data[1]); // shader = none
    try std.testing.expectEqual(@as(u8, 0), data[2]); // fogMode = color

    // Check offset slots are -1
    const id_offset = std.mem.readInt(i32, data[61..65], .little);
    const particle_offset = std.mem.readInt(i32, data[65..69], .little);
    try std.testing.expectEqual(@as(i32, -1), id_offset);
    try std.testing.expectEqual(@as(i32, -1), particle_offset);
}

test "FluidFXAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = FluidFXAsset{
        .id = "test_fluid",
        .shader = .water,
        .fog_mode = .color_light,
        .fog_color = common.Color{ .r = 0, .g = 100, .b = 200 },
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block + VarInt(10) + "test_fluid"
    try std.testing.expectEqual(@as(usize, 69 + 1 + 10), data.len);

    // Check nullBits has fogColor and id set
    try std.testing.expectEqual(@as(u8, 0x11), data[0]); // bit 0 + bit 4

    // Check shader and fogMode
    try std.testing.expectEqual(@as(u8, 6), data[1]); // shader = water
    try std.testing.expectEqual(@as(u8, 1), data[2]); // fogMode = color_light

    // Check fog color
    try std.testing.expectEqual(@as(u8, 0), data[3]);
    try std.testing.expectEqual(@as(u8, 100), data[4]);
    try std.testing.expectEqual(@as(u8, 200), data[5]);

    // Check id offset is 0 (starts at var block start)
    const id_offset = std.mem.readInt(i32, data[61..65], .little);
    try std.testing.expectEqual(@as(i32, 0), id_offset);
}
