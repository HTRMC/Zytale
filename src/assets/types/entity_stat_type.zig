/// EntityStatType Asset Type
///
/// Represents entity stat types like health, stamina, etc.

const std = @import("std");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;

/// Entity stat reset behavior
pub const EntityStatResetBehavior = enum(u8) {
    initial_value = 0,
    max_value = 1,
};

/// Entity part enum
pub const EntityPart = enum(u8) {
    self = 0,
    entity = 1,
    primary_item = 2,
    secondary_item = 3,
};

/// Vector3f (12 bytes)
pub const Vector3f = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn serialize(self: Vector3f, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [12]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], @bitCast(self.x), .little);
        std.mem.writeInt(u32, bytes[4..8], @bitCast(self.y), .little);
        std.mem.writeInt(u32, bytes[8..12], @bitCast(self.z), .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// Direction (12 bytes - yaw, pitch, roll)
pub const Direction = struct {
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    roll: f32 = 0.0,

    pub fn serialize(self: Direction, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [12]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], @bitCast(self.yaw), .little);
        std.mem.writeInt(u32, bytes[4..8], @bitCast(self.pitch), .little);
        std.mem.writeInt(u32, bytes[8..12], @bitCast(self.roll), .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// ModelParticle (42 bytes with offsets)
pub const ModelParticle = struct {
    system_id: ?[]const u8 = null,
    scale: f32 = 1.0,
    color: ?common.Color = null,
    target_entity_part: EntityPart = .self,
    target_node_name: ?[]const u8 = null,
    position_offset: ?Vector3f = null,
    rotation_offset: ?Direction = null,
    detached_from_model: bool = false,

    pub const FIXED_BLOCK_SIZE: u32 = 34;
    pub const VARIABLE_BLOCK_START: u32 = 42;

    pub fn serialize(self: ModelParticle, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.color != null) null_bits |= 0x01;
        if (self.position_offset != null) null_bits |= 0x02;
        if (self.rotation_offset != null) null_bits |= 0x04;
        if (self.system_id != null) null_bits |= 0x08;
        if (self.target_node_name != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // scale (f32 LE)
        try writeF32(buf, allocator, self.scale);

        // color (3 bytes, always written)
        if (self.color) |c| {
            try buf.appendSlice(allocator, &[_]u8{ c.r, c.g, c.b });
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // targetEntityPart (1 byte)
        try buf.append(allocator, @intFromEnum(self.target_entity_part));

        // positionOffset (12 bytes, always written)
        if (self.position_offset) |po| {
            try po.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // rotationOffset (12 bytes, always written)
        if (self.rotation_offset) |ro| {
            try ro.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // detachedFromModel (1 byte bool)
        try buf.append(allocator, if (self.detached_from_model) @as(u8, 1) else 0);

        // Reserve offset slots (8 bytes)
        const system_id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 }); // systemIdOffset

        const target_node_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 }); // targetNodeNameOffset

        // Variable block starts at position 42 relative to start
        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // systemId (if present)
        if (self.system_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[system_id_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[system_id_offset_slot..][0..4], -1, .little);
        }

        // targetNodeName (if present)
        if (self.target_node_name) |name| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[target_node_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(name.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, name);
        } else {
            std.mem.writeInt(i32, buf.items[target_node_offset_slot..][0..4], -1, .little);
        }
    }
};

/// EntityStatEffects (inline variable format)
pub const EntityStatEffects = struct {
    trigger_at_zero: bool = false,
    sound_event_index: i32 = -1,
    particles: ?[]const ModelParticle = null,

    pub const FIXED_BLOCK_SIZE: u32 = 6;

    pub fn serialize(self: EntityStatEffects, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.particles != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // triggerAtZero (1 byte bool)
        try buf.append(allocator, if (self.trigger_at_zero) @as(u8, 1) else 0);

        // soundEventIndex (i32 LE)
        var idx_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &idx_bytes, self.sound_event_index, .little);
        try buf.appendSlice(allocator, &idx_bytes);

        // particles array (inline)
        if (self.particles) |particles| {
            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(particles.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (particles) |particle| {
                try particle.serialize(buf, allocator);
            }
        }
    }
};

/// EntityStatType asset
pub const EntityStatTypeAsset = struct {
    /// Asset ID
    id: ?[]const u8 = null,

    /// Initial value
    value: f32 = 0.0,

    /// Minimum value
    min: f32 = 0.0,

    /// Maximum value
    max: f32 = 100.0,

    /// Effects when stat reaches min value
    min_value_effects: ?EntityStatEffects = null,

    /// Effects when stat reaches max value
    max_value_effects: ?EntityStatEffects = null,

    /// Reset behavior
    reset_behavior: EntityStatResetBehavior = .initial_value,

    const Self = @This();

    /// Protocol serialization constants
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 14;
    pub const VARIABLE_FIELD_COUNT: u32 = 3;
    pub const VARIABLE_BLOCK_START: u32 = 26;

    /// Serialize to protocol format
    /// Format: nullBits(1) + value(4) + min(4) + max(4) + resetBehavior(1) +
    ///         idOffset(4) + minValueEffectsOffset(4) + maxValueEffectsOffset(4) +
    ///         [variable: id, minValueEffects, maxValueEffects]
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.min_value_effects != null) null_bits |= 0x02;
        if (self.max_value_effects != null) null_bits |= 0x04;
        try buf.append(allocator, null_bits);

        // value (f32 LE)
        try writeF32(&buf, allocator, self.value);

        // min (f32 LE)
        try writeF32(&buf, allocator, self.min);

        // max (f32 LE)
        try writeF32(&buf, allocator, self.max);

        // resetBehavior (1 byte)
        try buf.append(allocator, @intFromEnum(self.reset_behavior));

        // Reserve offset slots (12 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 }); // idOffset

        const min_effects_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 }); // minValueEffectsOffset

        const max_effects_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 }); // maxValueEffectsOffset

        // Variable block starts at position 26
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

        // minValueEffects (if present)
        if (self.min_value_effects) |effects| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[min_effects_offset_slot..][0..4], offset, .little);
            try effects.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[min_effects_offset_slot..][0..4], -1, .little);
        }

        // maxValueEffects (if present)
        if (self.max_value_effects) |effects| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[max_effects_offset_slot..][0..4], offset, .little);
            try effects.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[max_effects_offset_slot..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.id) |id| allocator.free(id);
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

test "EntityStatTypeAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = EntityStatTypeAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 26 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 26), data.len);

    // Check nullBits is 0 (nothing set)
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check resetBehavior is initial_value
    try std.testing.expectEqual(@as(u8, 0), data[13]);

    // Check offset slots are -1
    const id_offset = std.mem.readInt(i32, data[14..18], .little);
    const min_offset = std.mem.readInt(i32, data[18..22], .little);
    const max_offset = std.mem.readInt(i32, data[22..26], .little);
    try std.testing.expectEqual(@as(i32, -1), id_offset);
    try std.testing.expectEqual(@as(i32, -1), min_offset);
    try std.testing.expectEqual(@as(i32, -1), max_offset);
}

test "EntityStatTypeAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = EntityStatTypeAsset{
        .id = "health",
        .value = 100.0,
        .max = 100.0,
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block (26) + VarInt(6) + "health"
    try std.testing.expectEqual(@as(usize, 26 + 1 + 6), data.len);

    // Check nullBits has id set
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);

    // Check id offset is 0 (starts at var block start)
    const id_offset = std.mem.readInt(i32, data[14..18], .little);
    try std.testing.expectEqual(@as(i32, 0), id_offset);
}
