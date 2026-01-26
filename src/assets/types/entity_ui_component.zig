/// EntityUIComponent Asset Type
///
/// Represents UI components for entities like health bars and combat text.

const std = @import("std");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;

/// Entity UI component type
pub const EntityUIType = enum(u8) {
    entity_stat = 0,
    combat_text = 1,
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

/// 2D float range (17 bytes)
pub const RangeVector2f = struct {
    x: ?Rangef = null,
    y: ?Rangef = null,

    pub fn serialize(self: RangeVector2f, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var null_bits: u8 = 0;
        if (self.x != null) null_bits |= 0x01;
        if (self.y != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // x (8 bytes, always written)
        if (self.x) |x| {
            try x.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // y (8 bytes, always written)
        if (self.y) |y| {
            try y.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }
    }
};

/// Combat text animation event type
pub const CombatTextAnimationEventType = enum(u8) {
    scale = 0,
    position = 1,
    opacity = 2,
};

/// Combat text animation event (34 bytes fixed)
pub const CombatTextAnimationEvent = struct {
    event_type: CombatTextAnimationEventType = .scale,
    start_at: f32 = 0.0,
    end_at: f32 = 0.0,
    start_scale: f32 = 1.0,
    end_scale: f32 = 1.0,
    position_offset: ?common.Vector2f = null,
    start_opacity: f32 = 1.0,
    end_opacity: f32 = 1.0,

    pub fn serialize(self: CombatTextAnimationEvent, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.position_offset != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // type
        try buf.append(allocator, @intFromEnum(self.event_type));

        // startAt
        try writeF32(buf, allocator, self.start_at);

        // endAt
        try writeF32(buf, allocator, self.end_at);

        // startScale
        try writeF32(buf, allocator, self.start_scale);

        // endScale
        try writeF32(buf, allocator, self.end_scale);

        // positionOffset (8 bytes, always written)
        if (self.position_offset) |po| {
            var pos_bytes: [8]u8 = undefined;
            po.serialize(&pos_bytes);
            try buf.appendSlice(allocator, &pos_bytes);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // startOpacity
        try writeF32(buf, allocator, self.start_opacity);

        // endOpacity
        try writeF32(buf, allocator, self.end_opacity);
    }
};

/// EntityUIComponent asset
pub const EntityUIComponentAsset = struct {
    /// UI component type
    ui_type: EntityUIType = .entity_stat,

    /// Hitbox offset (nullable)
    hitbox_offset: ?common.Vector2f = null,

    /// Unknown bool
    unknown: bool = false,

    /// Entity stat index
    entity_stat_index: i32 = 0,

    /// Random position offset range (nullable)
    combat_text_random_position_offset_range: ?RangeVector2f = null,

    /// Viewport margin
    combat_text_viewport_margin: f32 = 0.0,

    /// Duration
    combat_text_duration: f32 = 0.0,

    /// Hit angle modifier strength
    combat_text_hit_angle_modifier_strength: f32 = 0.0,

    /// Font size
    combat_text_font_size: f32 = 0.0,

    /// Text color (nullable)
    combat_text_color: ?common.Color = null,

    /// Animation events (nullable)
    combat_text_animation_events: ?[]const CombatTextAnimationEvent = null,

    const Self = @This();

    /// Protocol serialization constants
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 51;
    pub const VARIABLE_FIELD_COUNT: u32 = 1;
    pub const VARIABLE_BLOCK_START: u32 = 51;

    /// Serialize to protocol format
    /// Format: nullBits(1) + type(1) + hitboxOffset(8) + unknown(1) + entityStatIndex(4) +
    ///         combatTextRandomPositionOffsetRange(17) + combatTextViewportMargin(4) +
    ///         combatTextDuration(4) + combatTextHitAngleModifierStrength(4) + combatTextFontSize(4) +
    ///         combatTextColor(3) + [VarInt count + CombatTextAnimationEvent[]]
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.hitbox_offset != null) null_bits |= 0x01;
        if (self.combat_text_random_position_offset_range != null) null_bits |= 0x02;
        if (self.combat_text_color != null) null_bits |= 0x04;
        if (self.combat_text_animation_events != null) null_bits |= 0x08;
        try buf.append(allocator, null_bits);

        // type (1 byte)
        try buf.append(allocator, @intFromEnum(self.ui_type));

        // hitboxOffset (8 bytes, always written)
        if (self.hitbox_offset) |ho| {
            var offset_bytes: [8]u8 = undefined;
            ho.serialize(&offset_bytes);
            try buf.appendSlice(allocator, &offset_bytes);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // unknown (1 byte bool)
        try buf.append(allocator, if (self.unknown) @as(u8, 1) else 0);

        // entityStatIndex (i32 LE)
        var stat_idx_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &stat_idx_bytes, self.entity_stat_index, .little);
        try buf.appendSlice(allocator, &stat_idx_bytes);

        // combatTextRandomPositionOffsetRange (17 bytes, always written)
        if (self.combat_text_random_position_offset_range) |range| {
            try range.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 17);
        }

        // combatTextViewportMargin (f32 LE)
        try writeF32(&buf, allocator, self.combat_text_viewport_margin);

        // combatTextDuration (f32 LE)
        try writeF32(&buf, allocator, self.combat_text_duration);

        // combatTextHitAngleModifierStrength (f32 LE)
        try writeF32(&buf, allocator, self.combat_text_hit_angle_modifier_strength);

        // combatTextFontSize (f32 LE)
        try writeF32(&buf, allocator, self.combat_text_font_size);

        // combatTextColor (3 bytes, always written)
        if (self.combat_text_color) |c| {
            try buf.appendSlice(allocator, &[_]u8{ c.r, c.g, c.b });
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // combatTextAnimationEvents (inline variable array)
        if (self.combat_text_animation_events) |events| {
            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(events.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (events) |event| {
                try event.serialize(&buf, allocator);
            }
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.combat_text_animation_events) |events| {
            allocator.free(events);
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

test "EntityUIComponentAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = EntityUIComponentAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 51 bytes (no animation events)
    try std.testing.expectEqual(@as(usize, 51), data.len);

    // Check nullBits is 0 (nothing set)
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check type is entity_stat
    try std.testing.expectEqual(@as(u8, 0), data[1]);
}

test "EntityUIComponentAsset serialize with events" {
    const allocator = std.testing.allocator;

    const events = [_]CombatTextAnimationEvent{
        .{ .event_type = .scale, .start_at = 0.0, .end_at = 1.0 },
    };

    var asset = EntityUIComponentAsset{
        .ui_type = .combat_text,
        .combat_text_animation_events = &events,
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed (51) + VarInt(1) + 1 event (34)
    try std.testing.expectEqual(@as(usize, 51 + 1 + 34), data.len);

    // Check nullBits has animation events set
    try std.testing.expectEqual(@as(u8, 0x08), data[0]);

    // Check type is combat_text
    try std.testing.expectEqual(@as(u8, 1), data[1]);
}
