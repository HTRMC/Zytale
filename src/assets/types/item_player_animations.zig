/// ItemPlayerAnimations Asset Type
///
/// Represents player animations for items including wiggle, pullback, and camera settings.

const std = @import("std");
const entity_stat_type = @import("entity_stat_type.zig");
const Allocator = std.mem.Allocator;

// Re-export Vector3f from entity_stat_type
pub const Vector3f = entity_stat_type.Vector3f;

/// Camera target node
pub const CameraNode = enum(u8) {
    none = 0,
    head = 1,
    l_shoulder = 2,
    r_shoulder = 3,
    belly = 4,
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

/// Wiggle weights for item animation (40 bytes fixed, no nullBits)
pub const WiggleWeights = struct {
    x: f32 = 0.0,
    x_deceleration: f32 = 0.0,
    y: f32 = 0.0,
    y_deceleration: f32 = 0.0,
    z: f32 = 0.0,
    z_deceleration: f32 = 0.0,
    roll: f32 = 0.0,
    roll_deceleration: f32 = 0.0,
    pitch: f32 = 0.0,
    pitch_deceleration: f32 = 0.0,

    pub const SIZE: usize = 40;

    pub fn serialize(self: WiggleWeights, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.x);
        try writeF32(buf, allocator, self.x_deceleration);
        try writeF32(buf, allocator, self.y);
        try writeF32(buf, allocator, self.y_deceleration);
        try writeF32(buf, allocator, self.z);
        try writeF32(buf, allocator, self.z_deceleration);
        try writeF32(buf, allocator, self.roll);
        try writeF32(buf, allocator, self.roll_deceleration);
        try writeF32(buf, allocator, self.pitch);
        try writeF32(buf, allocator, self.pitch_deceleration);
    }
};

/// Item pullback configuration (49 bytes fixed)
pub const ItemPullbackConfiguration = struct {
    left_offset_override: ?Vector3f = null,
    left_rotation_override: ?Vector3f = null,
    right_offset_override: ?Vector3f = null,
    right_rotation_override: ?Vector3f = null,

    pub const SIZE: usize = 49;

    pub fn serialize(self: ItemPullbackConfiguration, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.left_offset_override != null) null_bits |= 0x01;
        if (self.left_rotation_override != null) null_bits |= 0x02;
        if (self.right_offset_override != null) null_bits |= 0x04;
        if (self.right_rotation_override != null) null_bits |= 0x08;
        try buf.append(allocator, null_bits);

        // leftOffsetOverride (12 bytes, always written)
        if (self.left_offset_override) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // leftRotationOverride (12 bytes, always written)
        if (self.left_rotation_override) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // rightOffsetOverride (12 bytes, always written)
        if (self.right_offset_override) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // rightRotationOverride (12 bytes, always written)
        if (self.right_rotation_override) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }
    }
};

/// Item animation (32 bytes fixed + variable strings)
pub const ItemAnimation = struct {
    third_person: ?[]const u8 = null,
    third_person_moving: ?[]const u8 = null,
    third_person_face: ?[]const u8 = null,
    first_person: ?[]const u8 = null,
    first_person_override: ?[]const u8 = null,
    keep_previous_first_person_animation: bool = false,
    speed: f32 = 0.0,
    blending_duration: f32 = 0.2,
    looping: bool = false,
    clips_geometry: bool = false,

    pub const FIXED_BLOCK_SIZE: u32 = 12;
    pub const VARIABLE_BLOCK_START: u32 = 32;

    pub fn serialize(self: ItemAnimation, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.third_person != null) null_bits |= 0x01;
        if (self.third_person_moving != null) null_bits |= 0x02;
        if (self.third_person_face != null) null_bits |= 0x04;
        if (self.first_person != null) null_bits |= 0x08;
        if (self.first_person_override != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // keepPreviousFirstPersonAnimation
        try buf.append(allocator, if (self.keep_previous_first_person_animation) @as(u8, 1) else 0);

        // speed
        try writeF32(buf, allocator, self.speed);

        // blendingDuration
        try writeF32(buf, allocator, self.blending_duration);

        // looping
        try buf.append(allocator, if (self.looping) @as(u8, 1) else 0);

        // clipsGeometry
        try buf.append(allocator, if (self.clips_geometry) @as(u8, 1) else 0);

        // Reserve 5 offset slots (20 bytes)
        const third_person_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const third_person_moving_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const third_person_face_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const first_person_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const first_person_override_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // thirdPerson
        if (self.third_person) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[third_person_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[third_person_offset_slot..][0..4], -1, .little);
        }

        // thirdPersonMoving
        if (self.third_person_moving) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[third_person_moving_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[third_person_moving_offset_slot..][0..4], -1, .little);
        }

        // thirdPersonFace
        if (self.third_person_face) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[third_person_face_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[third_person_face_offset_slot..][0..4], -1, .little);
        }

        // firstPerson
        if (self.first_person) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[first_person_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[first_person_offset_slot..][0..4], -1, .little);
        }

        // firstPersonOverride
        if (self.first_person_override) |s| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[first_person_override_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, s);
        } else {
            std.mem.writeInt(i32, buf.items[first_person_override_offset_slot..][0..4], -1, .little);
        }
    }
};

/// Camera axis settings (9 bytes fixed + inline variable array)
pub const CameraAxis = struct {
    angle_range: ?Rangef = null,
    target_nodes: ?[]const CameraNode = null,

    pub const FIXED_BLOCK_SIZE: u32 = 9;

    pub fn serialize(self: CameraAxis, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.angle_range != null) null_bits |= 0x01;
        if (self.target_nodes != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // angleRange (8 bytes, always written)
        if (self.angle_range) |r| {
            try r.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // targetNodes (inline variable array)
        if (self.target_nodes) |nodes| {
            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(nodes.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (nodes) |node| {
                try buf.append(allocator, @intFromEnum(node));
            }
        }
    }
};

/// Camera settings (21 bytes fixed + offset-based variable fields)
pub const CameraSettings = struct {
    position_offset: ?Vector3f = null,
    yaw: ?CameraAxis = null,
    pitch: ?CameraAxis = null,

    pub const FIXED_BLOCK_SIZE: u32 = 13;
    pub const VARIABLE_BLOCK_START: u32 = 21;

    pub fn serialize(self: CameraSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.position_offset != null) null_bits |= 0x01;
        if (self.yaw != null) null_bits |= 0x02;
        if (self.pitch != null) null_bits |= 0x04;
        try buf.append(allocator, null_bits);

        // positionOffset (12 bytes, always written)
        if (self.position_offset) |po| {
            try po.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // Reserve 2 offset slots (8 bytes)
        const yaw_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const pitch_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // yaw
        if (self.yaw) |y| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[yaw_offset_slot..][0..4], offset, .little);
            try y.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[yaw_offset_slot..][0..4], -1, .little);
        }

        // pitch
        if (self.pitch) |p| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[pitch_offset_slot..][0..4], offset, .little);
            try p.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[pitch_offset_slot..][0..4], -1, .little);
        }
    }
};

/// ItemPlayerAnimations animation entry (string-keyed)
pub const AnimationEntry = struct {
    key: []const u8,
    animation: ItemAnimation,
};

/// ItemPlayerAnimations asset (103 bytes fixed + variable)
pub const ItemPlayerAnimationsAsset = struct {
    id: ?[]const u8 = null,
    animations: ?[]const AnimationEntry = null,
    wiggle_weights: ?WiggleWeights = null,
    camera: ?CameraSettings = null,
    pullback_config: ?ItemPullbackConfiguration = null,
    use_first_person_override: bool = false,

    const Self = @This();

    pub const FIXED_BLOCK_SIZE: u32 = 91;
    pub const VARIABLE_BLOCK_START: u32 = 103;

    /// Serialize to protocol format
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.wiggle_weights != null) null_bits |= 0x01;
        if (self.pullback_config != null) null_bits |= 0x02;
        if (self.id != null) null_bits |= 0x04;
        if (self.animations != null) null_bits |= 0x08;
        if (self.camera != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // wiggleWeights (40 bytes, always written)
        if (self.wiggle_weights) |ww| {
            try ww.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 40);
        }

        // pullbackConfig (49 bytes, always written)
        if (self.pullback_config) |pc| {
            try pc.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 49);
        }

        // useFirstPersonOverride
        try buf.append(allocator, if (self.use_first_person_override) @as(u8, 1) else 0);

        // Reserve 3 offset slots (12 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const animations_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const camera_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // id string
        if (self.id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], -1, .little);
        }

        // animations dictionary
        if (self.animations) |anims| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[animations_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(anims.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (anims) |entry| {
                // Key (VarString)
                try writeVarString(&buf, allocator, entry.key);
                // Value (ItemAnimation)
                try entry.animation.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[animations_offset_slot..][0..4], -1, .little);
        }

        // camera
        if (self.camera) |cam| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[camera_offset_slot..][0..4], offset, .little);
            try cam.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[camera_offset_slot..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
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

fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(str.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);
    try buf.appendSlice(allocator, str);
}

test "ItemPlayerAnimationsAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = ItemPlayerAnimationsAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 103 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 103), data.len);

    // Check nullBits is 0 (nothing set)
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check offset slots are -1
    const id_offset = std.mem.readInt(i32, data[91..95], .little);
    const anims_offset = std.mem.readInt(i32, data[95..99], .little);
    const camera_offset = std.mem.readInt(i32, data[99..103], .little);
    try std.testing.expectEqual(@as(i32, -1), id_offset);
    try std.testing.expectEqual(@as(i32, -1), anims_offset);
    try std.testing.expectEqual(@as(i32, -1), camera_offset);
}

test "ItemPlayerAnimationsAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = ItemPlayerAnimationsAsset{
        .id = "sword_swing",
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed (103) + VarInt(11) + "sword_swing"
    try std.testing.expectEqual(@as(usize, 103 + 1 + 11), data.len);

    // Check nullBits has id set
    try std.testing.expectEqual(@as(u8, 0x04), data[0]);

    // Check id offset is 0
    const id_offset = std.mem.readInt(i32, data[91..95], .little);
    try std.testing.expectEqual(@as(i32, 0), id_offset);
}

test "WiggleWeights serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const ww = WiggleWeights{ .x = 1.0, .y = 2.0 };
    try ww.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 40), buf.items.len);
}

test "ItemAnimation serialize minimal" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const anim = ItemAnimation{};
    try anim.serialize(&buf, allocator);

    // Fixed block = 32 bytes (no strings)
    try std.testing.expectEqual(@as(usize, 32), buf.items.len);

    // Check nullBits is 0
    try std.testing.expectEqual(@as(u8, 0), buf.items[0]);
}
