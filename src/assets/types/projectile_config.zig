/// ProjectileConfig Asset Type
///
/// Represents projectile configuration with physics and model data.
/// FIXED_BLOCK_SIZE = 163 bytes (+ 8 bytes for 2 offset slots = 171 total)

const std = @import("std");
const entity_stat_type = @import("entity_stat_type.zig");
const Allocator = std.mem.Allocator;

// Re-export common types
pub const Vector3f = entity_stat_type.Vector3f;
pub const Direction = entity_stat_type.Direction;

// ============================================================================
// Enums
// ============================================================================

/// PhysicsType enum (1 byte)
pub const PhysicsType = enum(u8) {
    standard = 0,
};

/// RotationMode enum (1 byte)
pub const RotationMode = enum(u8) {
    none = 0,
    velocity = 1,
    velocity_damped = 2,
    velocity_roll = 3,
};

/// InteractionType enum (1 byte)
pub const InteractionType = enum(u8) {
    primary = 0,
    secondary = 1,
    ability1 = 2,
    ability2 = 3,
    ability3 = 4,
    use = 5,
    pick = 6,
    pickup = 7,
    collision_enter = 8,
    collision_leave = 9,
    collision = 10,
    entity_stat_effect = 11,
    swap_to = 12,
    swap_from = 13,
    death = 14,
    wielding = 15,
    projectile_spawn = 16,
    projectile_hit = 17,
    projectile_miss = 18,
    projectile_bounce = 19,
    held = 20,
    held_offhand = 21,
    equipped = 22,
    dodge = 23,
    game_mode_swap = 24,
};

/// Phobia enum (1 byte)
pub const Phobia = enum(u8) {
    none = 0,
    arachnophobia = 1,
    ophidiophobia = 2,
};

// ============================================================================
// Structs
// ============================================================================

/// PhysicsConfig (122 bytes)
pub const PhysicsConfig = struct {
    physics_type: PhysicsType = .standard,
    density: f64 = 0.0,
    gravity: f64 = 0.0,
    bounciness: f64 = 0.0,
    bounce_count: i32 = 0,
    bounce_limit: f64 = 0.0,
    sticks_vertically: bool = false,
    compute_yaw: bool = false,
    compute_pitch: bool = false,
    rotation_mode: RotationMode = .none,
    move_out_of_solid_speed: f64 = 0.0,
    terminal_velocity_air: f64 = 0.0,
    density_air: f64 = 0.0,
    terminal_velocity_water: f64 = 0.0,
    density_water: f64 = 0.0,
    hit_water_impulse_loss: f64 = 0.0,
    rotation_force: f64 = 0.0,
    speed_rotation_factor: f32 = 0.0,
    swimming_damping_factor: f64 = 0.0,
    allow_rolling: bool = false,
    rolling_friction_factor: f64 = 0.0,
    rolling_speed: f32 = 0.0,

    pub const SIZE: usize = 122;

    pub fn serialize(self: PhysicsConfig, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // type
        try buf.append(allocator, @intFromEnum(self.physics_type));
        // density
        try writeF64(buf, allocator, self.density);
        // gravity
        try writeF64(buf, allocator, self.gravity);
        // bounciness
        try writeF64(buf, allocator, self.bounciness);
        // bounceCount
        try writeI32(buf, allocator, self.bounce_count);
        // bounceLimit
        try writeF64(buf, allocator, self.bounce_limit);
        // sticksVertically
        try buf.append(allocator, if (self.sticks_vertically) @as(u8, 1) else 0);
        // computeYaw
        try buf.append(allocator, if (self.compute_yaw) @as(u8, 1) else 0);
        // computePitch
        try buf.append(allocator, if (self.compute_pitch) @as(u8, 1) else 0);
        // rotationMode
        try buf.append(allocator, @intFromEnum(self.rotation_mode));
        // moveOutOfSolidSpeed
        try writeF64(buf, allocator, self.move_out_of_solid_speed);
        // terminalVelocityAir
        try writeF64(buf, allocator, self.terminal_velocity_air);
        // densityAir
        try writeF64(buf, allocator, self.density_air);
        // terminalVelocityWater
        try writeF64(buf, allocator, self.terminal_velocity_water);
        // densityWater
        try writeF64(buf, allocator, self.density_water);
        // hitWaterImpulseLoss
        try writeF64(buf, allocator, self.hit_water_impulse_loss);
        // rotationForce
        try writeF64(buf, allocator, self.rotation_force);
        // speedRotationFactor
        try writeF32(buf, allocator, self.speed_rotation_factor);
        // swimmingDampingFactor
        try writeF64(buf, allocator, self.swimming_damping_factor);
        // allowRolling
        try buf.append(allocator, if (self.allow_rolling) @as(u8, 1) else 0);
        // rollingFrictionFactor
        try writeF64(buf, allocator, self.rolling_friction_factor);
        // rollingSpeed
        try writeF32(buf, allocator, self.rolling_speed);
    }
};

/// Hitbox (24 bytes)
pub const Hitbox = struct {
    min_x: f32 = 0.0,
    min_y: f32 = 0.0,
    min_z: f32 = 0.0,
    max_x: f32 = 0.0,
    max_y: f32 = 0.0,
    max_z: f32 = 0.0,

    pub const SIZE: usize = 24;

    pub fn serialize(self: Hitbox, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.min_x);
        try writeF32(buf, allocator, self.min_y);
        try writeF32(buf, allocator, self.min_z);
        try writeF32(buf, allocator, self.max_x);
        try writeF32(buf, allocator, self.max_y);
        try writeF32(buf, allocator, self.max_z);
    }
};

/// ColorLight (4 bytes)
pub const ColorLight = struct {
    radius: u8 = 0,
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,

    pub const SIZE: usize = 4;

    pub fn serialize(self: ColorLight, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.radius);
        try buf.append(allocator, self.red);
        try buf.append(allocator, self.green);
        try buf.append(allocator, self.blue);
    }
};

/// InteractionEntry for enum-keyed dictionary
pub const InteractionEntry = struct {
    interaction_type: InteractionType,
    value: i32,
};

/// Model (91 bytes fixed + 12 variable fields)
/// This is a minimal implementation - only supports empty/basic models
pub const Model = struct {
    asset_id: ?[]const u8 = null,
    path: ?[]const u8 = null,
    texture: ?[]const u8 = null,
    gradient_set: ?[]const u8 = null,
    gradient_id: ?[]const u8 = null,
    scale: f32 = 1.0,
    eye_height: f32 = 0.0,
    crouch_offset: f32 = 0.0,
    hitbox: ?Hitbox = null,
    light: ?ColorLight = null,
    phobia: Phobia = .none,
    // Note: camera, animationSets, attachments, particles, trails, detailBoxes, phobiaModel
    // are variable fields that are omitted in this minimal implementation

    pub const FIXED_BLOCK_SIZE: usize = 43;
    pub const VARIABLE_BLOCK_START: usize = 91;

    pub fn serialize(self: Model, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits (2 bytes)
        var null_bits: [2]u8 = .{ 0, 0 };
        if (self.hitbox != null) null_bits[0] |= 0x01;
        if (self.light != null) null_bits[0] |= 0x02;
        if (self.asset_id != null) null_bits[0] |= 0x04;
        if (self.path != null) null_bits[0] |= 0x08;
        if (self.texture != null) null_bits[0] |= 0x10;
        if (self.gradient_set != null) null_bits[0] |= 0x20;
        if (self.gradient_id != null) null_bits[0] |= 0x40;
        // bits 0x80, null_bits[1] are for variable fields we don't support
        try buf.appendSlice(allocator, &null_bits);

        // scale
        try writeF32(buf, allocator, self.scale);
        // eyeHeight
        try writeF32(buf, allocator, self.eye_height);
        // crouchOffset
        try writeF32(buf, allocator, self.crouch_offset);

        // hitbox (24 bytes, always written)
        if (self.hitbox) |hb| {
            try hb.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 24);
        }

        // light (4 bytes, always written)
        if (self.light) |l| {
            try l.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 4);
        }

        // phobia
        try buf.append(allocator, @intFromEnum(self.phobia));

        // Reserve 12 offset slots (48 bytes)
        const asset_id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const path_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const texture_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const gradient_set_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const gradient_id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const camera_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const animation_sets_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const attachments_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const particles_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const trails_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const detail_boxes_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const phobia_model_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // assetId
        if (self.asset_id) |aid| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[asset_id_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, aid);
        } else {
            std.mem.writeInt(i32, buf.items[asset_id_offset_slot..][0..4], -1, .little);
        }

        // path
        if (self.path) |p| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[path_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, p);
        } else {
            std.mem.writeInt(i32, buf.items[path_offset_slot..][0..4], -1, .little);
        }

        // texture
        if (self.texture) |t| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[texture_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, t);
        } else {
            std.mem.writeInt(i32, buf.items[texture_offset_slot..][0..4], -1, .little);
        }

        // gradientSet
        if (self.gradient_set) |gs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[gradient_set_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, gs);
        } else {
            std.mem.writeInt(i32, buf.items[gradient_set_offset_slot..][0..4], -1, .little);
        }

        // gradientId
        if (self.gradient_id) |gi| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[gradient_id_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, gi);
        } else {
            std.mem.writeInt(i32, buf.items[gradient_id_offset_slot..][0..4], -1, .little);
        }

        // camera - not implemented
        std.mem.writeInt(i32, buf.items[camera_offset_slot..][0..4], -1, .little);
        // animationSets - not implemented
        std.mem.writeInt(i32, buf.items[animation_sets_offset_slot..][0..4], -1, .little);
        // attachments - not implemented
        std.mem.writeInt(i32, buf.items[attachments_offset_slot..][0..4], -1, .little);
        // particles - not implemented
        std.mem.writeInt(i32, buf.items[particles_offset_slot..][0..4], -1, .little);
        // trails - not implemented
        std.mem.writeInt(i32, buf.items[trails_offset_slot..][0..4], -1, .little);
        // detailBoxes - not implemented
        std.mem.writeInt(i32, buf.items[detail_boxes_offset_slot..][0..4], -1, .little);
        // phobiaModel - not implemented
        std.mem.writeInt(i32, buf.items[phobia_model_offset_slot..][0..4], -1, .little);
    }
};

/// ProjectileConfig asset (163 bytes fixed + 8 bytes offsets = 171 total, + variable)
pub const ProjectileConfigAsset = struct {
    physics_config: ?PhysicsConfig = null,
    model: ?Model = null,
    launch_force: f64 = 0.0,
    spawn_offset: ?Vector3f = null,
    rotation_offset: ?Direction = null,
    interactions: ?[]const InteractionEntry = null,
    launch_local_sound_event_index: i32 = 0,
    projectile_sound_event_index: i32 = 0,

    const Self = @This();

    pub const FIXED_BLOCK_SIZE: u32 = 163;
    pub const VARIABLE_BLOCK_START: u32 = 171;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        const start_pos = buf.items.len;

        // nullBits (1 byte)
        var null_bits: u8 = 0;
        if (self.physics_config != null) null_bits |= 0x01;
        if (self.spawn_offset != null) null_bits |= 0x02;
        if (self.rotation_offset != null) null_bits |= 0x04;
        if (self.model != null) null_bits |= 0x08;
        if (self.interactions != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // physicsConfig (122 bytes, always written)
        if (self.physics_config) |pc| {
            try pc.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 122);
        }

        // launchForce
        try writeF64(&buf, allocator, self.launch_force);

        // spawnOffset (12 bytes, always written)
        if (self.spawn_offset) |so| {
            try so.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // rotationOffset (12 bytes, always written)
        if (self.rotation_offset) |ro| {
            try ro.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // launchLocalSoundEventIndex
        try writeI32(&buf, allocator, self.launch_local_sound_event_index);

        // projectileSoundEventIndex
        try writeI32(&buf, allocator, self.projectile_sound_event_index);

        // Reserve 2 offset slots (8 bytes)
        const model_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const interactions_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // model
        if (self.model) |m| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[model_offset_slot..][0..4], offset, .little);
            try m.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[model_offset_slot..][0..4], -1, .little);
        }

        // interactions (enum-keyed dictionary: InteractionType -> i32)
        if (self.interactions) |ints| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[interactions_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(ints.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (ints) |entry| {
                try buf.append(allocator, @intFromEnum(entry.interaction_type));
                try writeI32(&buf, allocator, entry.value);
            }
        } else {
            std.mem.writeInt(i32, buf.items[interactions_offset_slot..][0..4], -1, .little);
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

fn writeF64(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f64) !void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, @bitCast(value), .little);
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

// ============================================================================
// Tests
// ============================================================================

test "ProjectileConfigAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = ProjectileConfigAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 171 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 171), data.len);

    // Check nullBits is 0
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check offset slots are -1
    const model_offset = std.mem.readInt(i32, data[163..167], .little);
    const interactions_offset = std.mem.readInt(i32, data[167..171], .little);
    try std.testing.expectEqual(@as(i32, -1), model_offset);
    try std.testing.expectEqual(@as(i32, -1), interactions_offset);
}

test "ProjectileConfigAsset serialize with physics" {
    const allocator = std.testing.allocator;

    var asset = ProjectileConfigAsset{
        .physics_config = .{
            .gravity = -9.8,
            .density = 1.0,
        },
        .launch_force = 10.0,
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Still fixed block = 171 bytes
    try std.testing.expectEqual(@as(usize, 171), data.len);

    // Check nullBits has physics_config set
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);
}

test "PhysicsConfig serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const config = PhysicsConfig{
        .gravity = -9.8,
    };
    try config.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 122), buf.items.len);
}

test "Model serialize minimal" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const model = Model{};
    try model.serialize(&buf, allocator);

    // Fixed block = 91 bytes
    try std.testing.expectEqual(@as(usize, 91), buf.items.len);
}
