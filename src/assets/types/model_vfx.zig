/// ModelVFX Asset
///
/// Represents a model visual effect (highlighting, animation effects, etc).
/// Based on com/hypixel/hytale/protocol/ModelVFX.java

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");

pub const Color = common.Color;
pub const Vector2f = common.Vector2f;

/// SwitchTo enum - what happens when the effect ends
pub const SwitchTo = enum(u8) {
    disappear = 0,
    appear = 1,
    stay = 2,
};

/// EffectDirection enum - direction of the effect
pub const EffectDirection = enum(u8) {
    none = 0,
    bottom_to_top = 1,
    top_to_bottom = 2,
    center_to_edges = 3,
    edges_to_center = 4,
    random = 5,
};

/// LoopOption enum - how the animation loops
pub const LoopOption = enum(u8) {
    play_once = 0,
    loop = 1,
    ping_pong = 2,
};

/// CurveType enum - animation curve
pub const CurveType = enum(u8) {
    linear = 0,
    ease_in = 1,
    ease_out = 2,
    ease_in_out = 3,
};

/// ModelVFX asset
/// Format: nullBits(1) + fixed fields(48) + variable id string
pub const ModelVFXAsset = struct {
    id: ?[]const u8 = null,
    switch_to: SwitchTo = .disappear,
    effect_direction: EffectDirection = .none,
    animation_duration: f32 = 0.0,
    animation_range: ?Vector2f = null,
    loop_option: LoopOption = .play_once,
    curve_type: CurveType = .linear,
    highlight_color: ?Color = null,
    highlight_thickness: f32 = 0.0,
    use_bloom_on_highlight: bool = false,
    use_progressive_highlight: bool = false,
    noise_scale: ?Vector2f = null,
    noise_scroll_speed: ?Vector2f = null,
    post_color: ?Color = null,
    post_color_opacity: f32 = 0.0,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 49;
    pub const VARIABLE_FIELD_COUNT: u32 = 1;
    pub const VARIABLE_BLOCK_START: u32 = 49;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.animation_range != null) null_bits |= 0x01;
        if (self.highlight_color != null) null_bits |= 0x02;
        if (self.noise_scale != null) null_bits |= 0x04;
        if (self.noise_scroll_speed != null) null_bits |= 0x08;
        if (self.post_color != null) null_bits |= 0x10;
        if (self.id != null) null_bits |= 0x20;
        try buf.append(allocator, null_bits);

        // switchTo (1 byte)
        try buf.append(allocator, @intFromEnum(self.switch_to));

        // effectDirection (1 byte)
        try buf.append(allocator, @intFromEnum(self.effect_direction));

        // animationDuration (4 bytes f32 LE)
        try writeF32(&buf, allocator, self.animation_duration);

        // animationRange (8 bytes Vector2f or zeros)
        if (self.animation_range) |range| {
            try writeF32(&buf, allocator, range.x);
            try writeF32(&buf, allocator, range.y);
        } else {
            try buf.appendNTimes(allocator, 0, 8);
        }

        // loopOption (1 byte)
        try buf.append(allocator, @intFromEnum(self.loop_option));

        // curveType (1 byte)
        try buf.append(allocator, @intFromEnum(self.curve_type));

        // highlightColor (3 bytes or zeros)
        if (self.highlight_color) |color| {
            try buf.append(allocator, color.r);
            try buf.append(allocator, color.g);
            try buf.append(allocator, color.b);
        } else {
            try buf.appendNTimes(allocator, 0, 3);
        }

        // highlightThickness (4 bytes f32 LE)
        try writeF32(&buf, allocator, self.highlight_thickness);

        // useBloomOnHighlight (1 byte)
        try buf.append(allocator, if (self.use_bloom_on_highlight) @as(u8, 1) else 0);

        // useProgressiveHighlight (1 byte)
        try buf.append(allocator, if (self.use_progressive_highlight) @as(u8, 1) else 0);

        // noiseScale (8 bytes Vector2f or zeros)
        if (self.noise_scale) |scale| {
            try writeF32(&buf, allocator, scale.x);
            try writeF32(&buf, allocator, scale.y);
        } else {
            try buf.appendNTimes(allocator, 0, 8);
        }

        // noiseScrollSpeed (8 bytes Vector2f or zeros)
        if (self.noise_scroll_speed) |speed| {
            try writeF32(&buf, allocator, speed.x);
            try writeF32(&buf, allocator, speed.y);
        } else {
            try buf.appendNTimes(allocator, 0, 8);
        }

        // postColor (3 bytes or zeros)
        if (self.post_color) |color| {
            try buf.append(allocator, color.r);
            try buf.append(allocator, color.g);
            try buf.append(allocator, color.b);
        } else {
            try buf.appendNTimes(allocator, 0, 3);
        }

        // postColorOpacity (4 bytes f32 LE)
        try writeF32(&buf, allocator, self.post_color_opacity);

        // Variable section: id string (if present)
        if (self.id) |id_str| {
            try writeVarString(&buf, allocator, id_str);
        }

        return buf.toOwnedSlice(allocator);
    }
};

// Helper functions
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

test "ModelVFXAsset serialization minimal" {
    const allocator = std.testing.allocator;

    var vfx = ModelVFXAsset{};

    const data = try vfx.serialize(allocator);
    defer allocator.free(data);

    // Should produce exactly 49 bytes (fixed block only, no id)
    try std.testing.expectEqual(@as(usize, 49), data.len);

    // Check nullBits: nothing present (0x00)
    try std.testing.expectEqual(@as(u8, 0x00), data[0]);
}

test "ModelVFXAsset serialization with id" {
    const allocator = std.testing.allocator;

    var vfx = ModelVFXAsset{
        .id = "test_vfx",
        .switch_to = .appear,
        .animation_duration = 1.0,
    };

    const data = try vfx.serialize(allocator);
    defer allocator.free(data);

    // Should have 49 bytes fixed + id string
    try std.testing.expect(data.len > 49);

    // Check nullBits: id present (0x20)
    try std.testing.expectEqual(@as(u8, 0x20), data[0]);

    // Check switchTo = appear (1)
    try std.testing.expectEqual(@as(u8, 1), data[1]);
}

test "ModelVFXAsset serialization with all fields" {
    const allocator = std.testing.allocator;

    var vfx = ModelVFXAsset{
        .id = "full_vfx",
        .animation_range = .{ .x = 0.0, .y = 1.0 },
        .highlight_color = .{ .r = 255, .g = 0, .b = 0 },
        .noise_scale = .{ .x = 1.0, .y = 1.0 },
        .noise_scroll_speed = .{ .x = 0.1, .y = 0.2 },
        .post_color = .{ .r = 0, .g = 255, .b = 0 },
    };

    const data = try vfx.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: all flags set (0x3F)
    try std.testing.expectEqual(@as(u8, 0x3F), data[0]);
}
