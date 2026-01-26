/// Weather Asset Type
///
/// Represents weather configuration with sky, fog, colors, and particle effects.
/// FIXED_BLOCK_SIZE = 30 bytes (+ 96 bytes for 24 offset slots = 126 total)
/// 4 bytes nullBits, 24 variable fields

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Simple Structs
// ============================================================================

/// Color (3 bytes)
pub const Color = struct {
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,

    pub const SIZE: usize = 3;

    pub fn serialize(self: Color, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.red);
        try buf.append(allocator, self.green);
        try buf.append(allocator, self.blue);
    }
};

/// ColorAlpha (4 bytes)
pub const ColorAlpha = struct {
    alpha: u8 = 0,
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,

    pub const SIZE: usize = 4;

    pub fn serialize(self: ColorAlpha, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.alpha);
        try buf.append(allocator, self.red);
        try buf.append(allocator, self.green);
        try buf.append(allocator, self.blue);
    }
};

/// NearFar (8 bytes)
pub const NearFar = struct {
    near: f32 = 0.0,
    far: f32 = 0.0,

    pub const SIZE: usize = 8;

    pub fn serialize(self: NearFar, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.near);
        try writeF32(buf, allocator, self.far);
    }
};

/// FogOptions (18 bytes)
pub const FogOptions = struct {
    ignore_fog_limits: bool = false,
    effective_view_distance_multiplier: f32 = 0.0,
    fog_far_view_distance: f32 = 0.0,
    fog_height_camera_offset: f32 = 0.0,
    fog_height_camera_overriden: bool = false,
    fog_height_camera_fixed: f32 = 0.0,

    pub const SIZE: usize = 18;

    pub fn serialize(self: FogOptions, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, if (self.ignore_fog_limits) @as(u8, 1) else 0);
        try writeF32(buf, allocator, self.effective_view_distance_multiplier);
        try writeF32(buf, allocator, self.fog_far_view_distance);
        try writeF32(buf, allocator, self.fog_height_camera_offset);
        try buf.append(allocator, if (self.fog_height_camera_overriden) @as(u8, 1) else 0);
        try writeF32(buf, allocator, self.fog_height_camera_fixed);
    }
};

/// WeatherParticle (13 bytes fixed + inline variable)
pub const WeatherParticle = struct {
    system_id: ?[]const u8 = null,
    color: ?Color = null,
    scale: f32 = 0.0,
    is_overground_only: bool = false,
    position_offset_multiplier: f32 = 0.0,

    pub const FIXED_SIZE: usize = 13;

    pub fn serialize(self: WeatherParticle, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.color != null) null_bits |= 0x01;
        if (self.system_id != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // color (3 bytes, always written)
        if (self.color) |c| {
            try c.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // scale
        try writeF32(buf, allocator, self.scale);
        // isOvergroundOnly
        try buf.append(allocator, if (self.is_overground_only) @as(u8, 1) else 0);
        // positionOffsetMultiplier
        try writeF32(buf, allocator, self.position_offset_multiplier);

        // systemId (inline variable)
        if (self.system_id) |sid| {
            try writeVarString(buf, allocator, sid);
        }
    }
};

/// Cloud (13 bytes fixed + variable)
pub const Cloud = struct {
    texture: ?[]const u8 = null,
    speeds: ?[]const FloatFloatEntry = null,
    colors: ?[]const FloatColorAlphaEntry = null,

    pub const FIXED_SIZE: usize = 13;

    pub fn serialize(self: Cloud, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.texture != null) null_bits |= 0x01;
        if (self.speeds != null) null_bits |= 0x02;
        if (self.colors != null) null_bits |= 0x04;
        try buf.append(allocator, null_bits);

        // Reserve 3 offset slots
        const texture_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const speeds_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + FIXED_SIZE;

        // texture
        if (self.texture) |tex| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[texture_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, tex);
        } else {
            std.mem.writeInt(i32, buf.items[texture_offset_slot..][0..4], -1, .little);
        }

        // speeds (Map<float, float>)
        if (self.speeds) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[speeds_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(s.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (s) |entry| {
                try writeF32(buf, allocator, entry.key);
                try writeF32(buf, allocator, entry.value);
            }
        } else {
            std.mem.writeInt(i32, buf.items[speeds_offset_slot..][0..4], -1, .little);
        }

        // colors (Map<float, ColorAlpha>)
        if (self.colors) |c| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[colors_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(c.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (c) |entry| {
                try writeF32(buf, allocator, entry.key);
                try entry.value.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[colors_offset_slot..][0..4], -1, .little);
        }
    }
};

// ============================================================================
// Map Entry Types
// ============================================================================

pub const FloatFloatEntry = struct {
    key: f32,
    value: f32,
};

pub const FloatColorEntry = struct {
    key: f32,
    value: Color,
};

pub const FloatColorAlphaEntry = struct {
    key: f32,
    value: ColorAlpha,
};

pub const IntStringEntry = struct {
    key: i32,
    value: []const u8,
};

// ============================================================================
// WeatherAsset
// ============================================================================

/// Weather asset (126 bytes total = 30 fixed + 96 offset slots, + variable)
pub const WeatherAsset = struct {
    id: ?[]const u8 = null,
    tag_indexes: ?[]const i32 = null,
    stars: ?[]const u8 = null,
    moons: ?[]const IntStringEntry = null,
    clouds: ?[]const Cloud = null,
    sunlight_damping_multiplier: ?[]const FloatFloatEntry = null,
    sunlight_colors: ?[]const FloatColorEntry = null,
    sky_top_colors: ?[]const FloatColorAlphaEntry = null,
    sky_bottom_colors: ?[]const FloatColorAlphaEntry = null,
    sky_sunset_colors: ?[]const FloatColorAlphaEntry = null,
    sun_colors: ?[]const FloatColorAlphaEntry = null,
    sun_scales: ?[]const FloatFloatEntry = null,
    sun_glow_colors: ?[]const FloatColorAlphaEntry = null,
    moon_colors: ?[]const FloatColorAlphaEntry = null,
    moon_scales: ?[]const FloatFloatEntry = null,
    moon_glow_colors: ?[]const FloatColorAlphaEntry = null,
    fog_colors: ?[]const FloatColorEntry = null,
    fog_height_falloffs: ?[]const FloatFloatEntry = null,
    fog_densities: ?[]const FloatFloatEntry = null,
    screen_effect: ?[]const u8 = null,
    screen_effect_colors: ?[]const FloatColorAlphaEntry = null,
    color_filters: ?[]const FloatColorEntry = null,
    water_tints: ?[]const FloatColorEntry = null,
    particle: ?WeatherParticle = null,
    fog: ?NearFar = null,
    fog_options: ?FogOptions = null,

    const Self = @This();

    pub const FIXED_BLOCK_SIZE: u32 = 30;
    pub const VARIABLE_BLOCK_START: u32 = 126;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        const start_pos = buf.items.len;

        // nullBits (4 bytes)
        var null_bits: [4]u8 = .{ 0, 0, 0, 0 };
        if (self.fog != null) null_bits[0] |= 0x01;
        if (self.fog_options != null) null_bits[0] |= 0x02;
        if (self.id != null) null_bits[0] |= 0x04;
        if (self.tag_indexes != null) null_bits[0] |= 0x08;
        if (self.stars != null) null_bits[0] |= 0x10;
        if (self.moons != null) null_bits[0] |= 0x20;
        if (self.clouds != null) null_bits[0] |= 0x40;
        if (self.sunlight_damping_multiplier != null) null_bits[0] |= 0x80;
        if (self.sunlight_colors != null) null_bits[1] |= 0x01;
        if (self.sky_top_colors != null) null_bits[1] |= 0x02;
        if (self.sky_bottom_colors != null) null_bits[1] |= 0x04;
        if (self.sky_sunset_colors != null) null_bits[1] |= 0x08;
        if (self.sun_colors != null) null_bits[1] |= 0x10;
        if (self.sun_scales != null) null_bits[1] |= 0x20;
        if (self.sun_glow_colors != null) null_bits[1] |= 0x40;
        if (self.moon_colors != null) null_bits[1] |= 0x80;
        if (self.moon_scales != null) null_bits[2] |= 0x01;
        if (self.moon_glow_colors != null) null_bits[2] |= 0x02;
        if (self.fog_colors != null) null_bits[2] |= 0x04;
        if (self.fog_height_falloffs != null) null_bits[2] |= 0x08;
        if (self.fog_densities != null) null_bits[2] |= 0x10;
        if (self.screen_effect != null) null_bits[2] |= 0x20;
        if (self.screen_effect_colors != null) null_bits[2] |= 0x40;
        if (self.color_filters != null) null_bits[2] |= 0x80;
        if (self.water_tints != null) null_bits[3] |= 0x01;
        if (self.particle != null) null_bits[3] |= 0x02;
        try buf.appendSlice(allocator, &null_bits);

        // fog (8 bytes, always written)
        if (self.fog) |f| {
            try f.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // fogOptions (18 bytes, always written)
        if (self.fog_options) |fo| {
            try fo.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 18);
        }

        // Reserve 24 offset slots (96 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const tag_indexes_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const stars_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const moons_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const clouds_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sunlight_damping_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sunlight_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sky_top_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sky_bottom_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sky_sunset_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sun_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sun_scales_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const sun_glow_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const moon_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const moon_scales_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const moon_glow_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const fog_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const fog_height_falloffs_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const fog_densities_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const screen_effect_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const screen_effect_colors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const color_filters_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const water_tints_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const particle_offset_slot = buf.items.len;
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

        // tagIndexes
        if (self.tag_indexes) |ti| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[tag_indexes_offset_slot..][0..4], offset, .little);
            try writeIntArray(&buf, allocator, ti);
        } else {
            std.mem.writeInt(i32, buf.items[tag_indexes_offset_slot..][0..4], -1, .little);
        }

        // stars
        if (self.stars) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[stars_offset_slot..][0..4], offset, .little);
            try writeVarString(&buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[stars_offset_slot..][0..4], -1, .little);
        }

        // moons (Map<int, String>)
        if (self.moons) |m| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[moons_offset_slot..][0..4], offset, .little);
            try writeIntStringMap(&buf, allocator, m);
        } else {
            std.mem.writeInt(i32, buf.items[moons_offset_slot..][0..4], -1, .little);
        }

        // clouds
        if (self.clouds) |c| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[clouds_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(c.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (c) |cloud| {
                try cloud.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[clouds_offset_slot..][0..4], -1, .little);
        }

        // sunlightDampingMultiplier (Map<float, float>)
        if (self.sunlight_damping_multiplier) |sdm| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sunlight_damping_offset_slot..][0..4], offset, .little);
            try writeFloatFloatMap(&buf, allocator, sdm);
        } else {
            std.mem.writeInt(i32, buf.items[sunlight_damping_offset_slot..][0..4], -1, .little);
        }

        // sunlightColors (Map<float, Color>)
        if (self.sunlight_colors) |sc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sunlight_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorMap(&buf, allocator, sc);
        } else {
            std.mem.writeInt(i32, buf.items[sunlight_colors_offset_slot..][0..4], -1, .little);
        }

        // skyTopColors (Map<float, ColorAlpha>)
        if (self.sky_top_colors) |stc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sky_top_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, stc);
        } else {
            std.mem.writeInt(i32, buf.items[sky_top_colors_offset_slot..][0..4], -1, .little);
        }

        // skyBottomColors
        if (self.sky_bottom_colors) |sbc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sky_bottom_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, sbc);
        } else {
            std.mem.writeInt(i32, buf.items[sky_bottom_colors_offset_slot..][0..4], -1, .little);
        }

        // skySunsetColors
        if (self.sky_sunset_colors) |ssc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sky_sunset_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, ssc);
        } else {
            std.mem.writeInt(i32, buf.items[sky_sunset_colors_offset_slot..][0..4], -1, .little);
        }

        // sunColors
        if (self.sun_colors) |sc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sun_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, sc);
        } else {
            std.mem.writeInt(i32, buf.items[sun_colors_offset_slot..][0..4], -1, .little);
        }

        // sunScales
        if (self.sun_scales) |ss| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sun_scales_offset_slot..][0..4], offset, .little);
            try writeFloatFloatMap(&buf, allocator, ss);
        } else {
            std.mem.writeInt(i32, buf.items[sun_scales_offset_slot..][0..4], -1, .little);
        }

        // sunGlowColors
        if (self.sun_glow_colors) |sgc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[sun_glow_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, sgc);
        } else {
            std.mem.writeInt(i32, buf.items[sun_glow_colors_offset_slot..][0..4], -1, .little);
        }

        // moonColors
        if (self.moon_colors) |mc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[moon_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, mc);
        } else {
            std.mem.writeInt(i32, buf.items[moon_colors_offset_slot..][0..4], -1, .little);
        }

        // moonScales
        if (self.moon_scales) |ms| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[moon_scales_offset_slot..][0..4], offset, .little);
            try writeFloatFloatMap(&buf, allocator, ms);
        } else {
            std.mem.writeInt(i32, buf.items[moon_scales_offset_slot..][0..4], -1, .little);
        }

        // moonGlowColors
        if (self.moon_glow_colors) |mgc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[moon_glow_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, mgc);
        } else {
            std.mem.writeInt(i32, buf.items[moon_glow_colors_offset_slot..][0..4], -1, .little);
        }

        // fogColors
        if (self.fog_colors) |fc| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[fog_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorMap(&buf, allocator, fc);
        } else {
            std.mem.writeInt(i32, buf.items[fog_colors_offset_slot..][0..4], -1, .little);
        }

        // fogHeightFalloffs
        if (self.fog_height_falloffs) |fhf| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[fog_height_falloffs_offset_slot..][0..4], offset, .little);
            try writeFloatFloatMap(&buf, allocator, fhf);
        } else {
            std.mem.writeInt(i32, buf.items[fog_height_falloffs_offset_slot..][0..4], -1, .little);
        }

        // fogDensities
        if (self.fog_densities) |fd| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[fog_densities_offset_slot..][0..4], offset, .little);
            try writeFloatFloatMap(&buf, allocator, fd);
        } else {
            std.mem.writeInt(i32, buf.items[fog_densities_offset_slot..][0..4], -1, .little);
        }

        // screenEffect
        if (self.screen_effect) |se| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[screen_effect_offset_slot..][0..4], offset, .little);
            try writeVarString(&buf, allocator, se);
        } else {
            std.mem.writeInt(i32, buf.items[screen_effect_offset_slot..][0..4], -1, .little);
        }

        // screenEffectColors
        if (self.screen_effect_colors) |sec| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[screen_effect_colors_offset_slot..][0..4], offset, .little);
            try writeFloatColorAlphaMap(&buf, allocator, sec);
        } else {
            std.mem.writeInt(i32, buf.items[screen_effect_colors_offset_slot..][0..4], -1, .little);
        }

        // colorFilters
        if (self.color_filters) |cf| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[color_filters_offset_slot..][0..4], offset, .little);
            try writeFloatColorMap(&buf, allocator, cf);
        } else {
            std.mem.writeInt(i32, buf.items[color_filters_offset_slot..][0..4], -1, .little);
        }

        // waterTints
        if (self.water_tints) |wt| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[water_tints_offset_slot..][0..4], offset, .little);
            try writeFloatColorMap(&buf, allocator, wt);
        } else {
            std.mem.writeInt(i32, buf.items[water_tints_offset_slot..][0..4], -1, .little);
        }

        // particle
        if (self.particle) |p| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[particle_offset_slot..][0..4], offset, .little);
            try p.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[particle_offset_slot..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Helper functions
// ============================================================================

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeVarIntBuf(buf_out: *[5]u8, value: i32) usize {
    var v: u32 = @bitCast(value);
    var i: usize = 0;
    while (v >= 0x80) {
        buf_out[i] = @truncate((v & 0x7F) | 0x80);
        v >>= 7;
        i += 1;
    }
    buf_out[i] = @truncate(v);
    return i + 1;
}

fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(str.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);
    try buf.appendSlice(allocator, str);
}

fn writeIntArray(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, arr: []const i32) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(arr.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);

    for (arr) |val| {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &bytes, val, .little);
        try buf.appendSlice(allocator, &bytes);
    }
}

fn writeIntStringMap(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, entries: []const IntStringEntry) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(entries.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);

    for (entries) |entry| {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &bytes, entry.key, .little);
        try buf.appendSlice(allocator, &bytes);
        try writeVarString(buf, allocator, entry.value);
    }
}

fn writeFloatFloatMap(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, entries: []const FloatFloatEntry) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(entries.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);

    for (entries) |entry| {
        try writeF32(buf, allocator, entry.key);
        try writeF32(buf, allocator, entry.value);
    }
}

fn writeFloatColorMap(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, entries: []const FloatColorEntry) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(entries.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);

    for (entries) |entry| {
        try writeF32(buf, allocator, entry.key);
        try entry.value.serialize(buf, allocator);
    }
}

fn writeFloatColorAlphaMap(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, entries: []const FloatColorAlphaEntry) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(entries.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);

    for (entries) |entry| {
        try writeF32(buf, allocator, entry.key);
        try entry.value.serialize(buf, allocator);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "WeatherAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = WeatherAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 126 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 126), data.len);

    // Check nullBits are 0
    try std.testing.expectEqual(@as(u8, 0), data[0]);
    try std.testing.expectEqual(@as(u8, 0), data[1]);
    try std.testing.expectEqual(@as(u8, 0), data[2]);
    try std.testing.expectEqual(@as(u8, 0), data[3]);
}

test "WeatherAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = WeatherAsset{
        .id = "clear_sky",
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed (126) + VarInt(9) + "clear_sky"
    try std.testing.expectEqual(@as(usize, 126 + 1 + 9), data.len);

    // Check nullBits[0] has id set (bit 2)
    try std.testing.expectEqual(@as(u8, 0x04), data[0]);
}

test "NearFar serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const nf = NearFar{ .near = 10.0, .far = 100.0 };
    try nf.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 8), buf.items.len);
}

test "FogOptions serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const fo = FogOptions{
        .ignore_fog_limits = true,
        .effective_view_distance_multiplier = 1.0,
    };
    try fo.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 18), buf.items.len);
}
