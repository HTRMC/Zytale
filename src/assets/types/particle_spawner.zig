/// ParticleSpawner Asset Type
///
/// Represents individual particle spawners with full particle configuration.
/// FIXED_BLOCK_SIZE = 131 bytes (+ 16 bytes for 4 offset slots = 147 total)
/// 2 bytes nullBits, 4 variable fields

const std = @import("std");
const particle_system = @import("particle_system.zig");
const Allocator = std.mem.Allocator;

// Re-export common types from particle_system
pub const Vector3f = particle_system.Vector3f;
pub const Rangef = particle_system.Rangef;
pub const RangeVector3f = particle_system.RangeVector3f;
pub const InitialVelocity = particle_system.InitialVelocity;
pub const ParticleAttractor = particle_system.ParticleAttractor;

// ============================================================================
// Enums
// ============================================================================

/// EmitShape enum (1 byte)
pub const EmitShape = enum(u8) {
    sphere = 0,
    cube = 1,
};

/// FXRenderMode enum (1 byte)
pub const FXRenderMode = enum(u8) {
    blend_linear = 0,
    blend_add = 1,
    erosion = 2,
    distortion = 3,
};

/// ParticleRotationInfluence enum (1 byte)
pub const ParticleRotationInfluence = enum(u8) {
    none = 0,
    billboard = 1,
    billboard_y = 2,
    billboard_velocity = 3,
    velocity = 4,
};

/// ParticleCollisionBlockType enum (1 byte)
pub const ParticleCollisionBlockType = enum(u8) {
    none = 0,
    air = 1,
    solid = 2,
    all = 3,
};

/// ParticleCollisionAction enum (1 byte)
pub const ParticleCollisionAction = enum(u8) {
    expire = 0,
    last_frame = 1,
    linger = 2,
};

/// ParticleUVOption enum (1 byte)
pub const ParticleUVOption = enum(u8) {
    none = 0,
    random_flip_u = 1,
    random_flip_v = 2,
    random_flip_uv = 3,
    flip_u = 4,
    flip_v = 5,
    flip_uv = 6,
};

/// ParticleScaleRatioConstraint enum (1 byte)
pub const ParticleScaleRatioConstraint = enum(u8) {
    one_to_one = 0,
    preserved = 1,
    none = 2,
};

/// SoftParticle enum (1 byte)
pub const SoftParticle = enum(u8) {
    enable = 0,
    disable = 1,
    require = 2,
};

/// UVMotionCurveType enum (1 byte)
pub const UVMotionCurveType = enum(u8) {
    constant = 0,
    increase_linear = 1,
    increase_quart_in = 2,
    increase_quart_in_out = 3,
    increase_quart_out = 4,
    decrease_linear = 5,
    decrease_quart_in = 6,
    decrease_quart_in_out = 7,
    decrease_quart_out = 8,
};

// ============================================================================
// Simple structs
// ============================================================================

/// Integer range (8 bytes)
pub const Range = struct {
    min: i32 = 0,
    max: i32 = 0,

    pub fn serialize(self: Range, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeI32(buf, allocator, self.min);
        try writeI32(buf, allocator, self.max);
    }
};

/// Color (3 bytes)
pub const Color = struct {
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,

    pub fn serialize(self: Color, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.red);
        try buf.append(allocator, self.green);
        try buf.append(allocator, self.blue);
    }
};

/// Size (8 bytes)
pub const Size = struct {
    width: i32 = 0,
    height: i32 = 0,

    pub fn serialize(self: Size, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeI32(buf, allocator, self.width);
        try writeI32(buf, allocator, self.height);
    }
};

/// ParticleCollision (3 bytes)
pub const ParticleCollision = struct {
    block_type: ParticleCollisionBlockType = .none,
    action: ParticleCollisionAction = .expire,
    particle_rotation_influence: ParticleRotationInfluence = .none,

    pub const SIZE: usize = 3;

    pub fn serialize(self: ParticleCollision, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, @intFromEnum(self.block_type));
        try buf.append(allocator, @intFromEnum(self.action));
        try buf.append(allocator, @intFromEnum(self.particle_rotation_influence));
    }
};

/// IntersectionHighlight (8 bytes)
pub const IntersectionHighlight = struct {
    highlight_threshold: f32 = 0.0,
    highlight_color: ?Color = null,

    pub const SIZE: usize = 8;

    pub fn serialize(self: IntersectionHighlight, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.highlight_color != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // highlightThreshold
        try writeF32(buf, allocator, self.highlight_threshold);

        // highlightColor (3 bytes, always written)
        if (self.highlight_color) |c| {
            try c.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }
    }
};

/// RangeVector2f (17 bytes)
pub const RangeVector2f = struct {
    x: ?Rangef = null,
    y: ?Rangef = null,

    pub const SIZE: usize = 17;

    pub fn serialize(self: RangeVector2f, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.x != null) null_bits |= 0x01;
        if (self.y != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // x (8 bytes, always written)
        if (self.x) |xv| {
            try xv.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // y (8 bytes, always written)
        if (self.y) |yv| {
            try yv.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }
    }
};

/// ParticleAnimationFrame (58 bytes)
pub const ParticleAnimationFrame = struct {
    frame_index: ?Range = null,
    scale: ?RangeVector2f = null,
    rotation: ?RangeVector3f = null,
    color: ?Color = null,
    opacity: f32 = 0.0,

    pub const SIZE: usize = 58;

    pub fn serialize(self: ParticleAnimationFrame, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.frame_index != null) null_bits |= 0x01;
        if (self.scale != null) null_bits |= 0x02;
        if (self.rotation != null) null_bits |= 0x04;
        if (self.color != null) null_bits |= 0x08;
        try buf.append(allocator, null_bits);

        // frameIndex (8 bytes, always written)
        if (self.frame_index) |fi| {
            try fi.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // scale (17 bytes, always written)
        if (self.scale) |s| {
            try s.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 17);
        }

        // rotation (25 bytes, always written)
        if (self.rotation) |r| {
            try r.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 25);
        }

        // color (3 bytes, always written)
        if (self.color) |c| {
            try c.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // opacity
        try writeF32(buf, allocator, self.opacity);
    }
};

/// UVMotion (19 bytes fixed + inline variable)
pub const UVMotion = struct {
    texture: ?[]const u8 = null,
    add_random_uv_offset: bool = false,
    speed_x: f32 = 0.0,
    speed_y: f32 = 0.0,
    scale: f32 = 0.0,
    strength: f32 = 0.0,
    strength_curve_type: UVMotionCurveType = .constant,

    pub const FIXED_BLOCK_SIZE: usize = 19;

    pub fn serialize(self: UVMotion, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.texture != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // addRandomUVOffset
        try buf.append(allocator, if (self.add_random_uv_offset) @as(u8, 1) else 0);

        // speedX
        try writeF32(buf, allocator, self.speed_x);

        // speedY
        try writeF32(buf, allocator, self.speed_y);

        // scale
        try writeF32(buf, allocator, self.scale);

        // strength
        try writeF32(buf, allocator, self.strength);

        // strengthCurveType
        try buf.append(allocator, @intFromEnum(self.strength_curve_type));

        // texture (inline variable - immediately follows fixed block)
        if (self.texture) |tex| {
            try writeVarString(buf, allocator, tex);
        }
    }
};

/// AnimationFrameEntry for int-keyed dictionary
pub const AnimationFrameEntry = struct {
    key: i32,
    frame: ParticleAnimationFrame,
};

/// Particle (133 bytes fixed + 2 variable fields)
pub const Particle = struct {
    texture_path: ?[]const u8 = null,
    frame_size: ?Size = null,
    uv_option: ParticleUVOption = .none,
    scale_ratio_constraint: ParticleScaleRatioConstraint = .one_to_one,
    soft_particles: SoftParticle = .enable,
    soft_particles_fade_factor: f32 = 0.0,
    use_sprite_blending: bool = false,
    initial_animation_frame: ?ParticleAnimationFrame = null,
    collision_animation_frame: ?ParticleAnimationFrame = null,
    animation_frames: ?[]const AnimationFrameEntry = null,

    pub const FIXED_BLOCK_SIZE: usize = 133;
    pub const VARIABLE_BLOCK_START: usize = 141;

    pub fn serialize(self: Particle, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits (1 byte)
        var null_bits: u8 = 0;
        if (self.frame_size != null) null_bits |= 0x01;
        if (self.initial_animation_frame != null) null_bits |= 0x02;
        if (self.collision_animation_frame != null) null_bits |= 0x04;
        if (self.texture_path != null) null_bits |= 0x08;
        if (self.animation_frames != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // frameSize (8 bytes, always written)
        if (self.frame_size) |fs| {
            try fs.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // uvOption
        try buf.append(allocator, @intFromEnum(self.uv_option));

        // scaleRatioConstraint
        try buf.append(allocator, @intFromEnum(self.scale_ratio_constraint));

        // softParticles
        try buf.append(allocator, @intFromEnum(self.soft_particles));

        // softParticlesFadeFactor
        try writeF32(buf, allocator, self.soft_particles_fade_factor);

        // useSpriteBlending
        try buf.append(allocator, if (self.use_sprite_blending) @as(u8, 1) else 0);

        // initialAnimationFrame (58 bytes, always written)
        if (self.initial_animation_frame) |iaf| {
            try iaf.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 58);
        }

        // collisionAnimationFrame (58 bytes, always written)
        if (self.collision_animation_frame) |caf| {
            try caf.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 58);
        }

        // Reserve 2 offset slots (8 bytes)
        const texture_path_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const animation_frames_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // texturePath
        if (self.texture_path) |tp| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[texture_path_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, tp);
        } else {
            std.mem.writeInt(i32, buf.items[texture_path_offset_slot..][0..4], -1, .little);
        }

        // animationFrames (int-keyed dictionary)
        if (self.animation_frames) |frames| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[animation_frames_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(frames.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (frames) |entry| {
                try writeI32(buf, allocator, entry.key);
                try entry.frame.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[animation_frames_offset_slot..][0..4], -1, .little);
        }
    }
};

/// ParticleSpawner asset (131 bytes fixed + 16 bytes offsets = 147 total, + variable)
pub const ParticleSpawnerAsset = struct {
    id: ?[]const u8 = null,
    particle: ?Particle = null,
    shape: EmitShape = .sphere,
    emit_offset: ?RangeVector3f = null,
    camera_offset: f32 = 0.0,
    use_emit_direction: bool = false,
    life_span: f32 = 0.0,
    spawn_rate: ?Rangef = null,
    spawn_burst: bool = false,
    wave_delay: ?Rangef = null,
    total_particles: ?Range = null,
    max_concurrent_particles: i32 = 0,
    initial_velocity: ?InitialVelocity = null,
    velocity_stretch_multiplier: f32 = 0.0,
    particle_rotation_influence: ParticleRotationInfluence = .none,
    particle_rotate_with_spawner: bool = false,
    is_low_res: bool = false,
    trail_spawner_position_multiplier: f32 = 0.0,
    trail_spawner_rotation_multiplier: f32 = 0.0,
    particle_collision: ?ParticleCollision = null,
    render_mode: FXRenderMode = .blend_linear,
    light_influence: f32 = 0.0,
    linear_filtering: bool = false,
    particle_life_span: ?Rangef = null,
    uv_motion: ?UVMotion = null,
    attractors: ?[]const ParticleAttractor = null,
    intersection_highlight: ?IntersectionHighlight = null,

    const Self = @This();

    pub const FIXED_BLOCK_SIZE: u32 = 131;
    pub const VARIABLE_BLOCK_START: u32 = 147;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        const start_pos = buf.items.len;

        // nullBits (2 bytes)
        var null_bits: [2]u8 = .{ 0, 0 };
        if (self.emit_offset != null) null_bits[0] |= 0x01;
        if (self.spawn_rate != null) null_bits[0] |= 0x02;
        if (self.wave_delay != null) null_bits[0] |= 0x04;
        if (self.total_particles != null) null_bits[0] |= 0x08;
        if (self.initial_velocity != null) null_bits[0] |= 0x10;
        if (self.particle_collision != null) null_bits[0] |= 0x20;
        if (self.particle_life_span != null) null_bits[0] |= 0x40;
        if (self.intersection_highlight != null) null_bits[0] |= 0x80;
        if (self.id != null) null_bits[1] |= 0x01;
        if (self.particle != null) null_bits[1] |= 0x02;
        if (self.uv_motion != null) null_bits[1] |= 0x04;
        if (self.attractors != null) null_bits[1] |= 0x08;
        try buf.appendSlice(allocator, &null_bits);

        // shape
        try buf.append(allocator, @intFromEnum(self.shape));

        // emitOffset (25 bytes, always written)
        if (self.emit_offset) |eo| {
            try eo.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 25);
        }

        // cameraOffset
        try writeF32(&buf, allocator, self.camera_offset);

        // useEmitDirection
        try buf.append(allocator, if (self.use_emit_direction) @as(u8, 1) else 0);

        // lifeSpan
        try writeF32(&buf, allocator, self.life_span);

        // spawnRate (8 bytes, always written)
        if (self.spawn_rate) |sr| {
            try sr.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // spawnBurst
        try buf.append(allocator, if (self.spawn_burst) @as(u8, 1) else 0);

        // waveDelay (8 bytes, always written)
        if (self.wave_delay) |wd| {
            try wd.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // totalParticles (8 bytes, always written)
        if (self.total_particles) |tp| {
            try tp.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // maxConcurrentParticles
        try writeI32(&buf, allocator, self.max_concurrent_particles);

        // initialVelocity (25 bytes, always written)
        if (self.initial_velocity) |iv| {
            try iv.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 25);
        }

        // velocityStretchMultiplier
        try writeF32(&buf, allocator, self.velocity_stretch_multiplier);

        // particleRotationInfluence
        try buf.append(allocator, @intFromEnum(self.particle_rotation_influence));

        // particleRotateWithSpawner
        try buf.append(allocator, if (self.particle_rotate_with_spawner) @as(u8, 1) else 0);

        // isLowRes
        try buf.append(allocator, if (self.is_low_res) @as(u8, 1) else 0);

        // trailSpawnerPositionMultiplier
        try writeF32(&buf, allocator, self.trail_spawner_position_multiplier);

        // trailSpawnerRotationMultiplier
        try writeF32(&buf, allocator, self.trail_spawner_rotation_multiplier);

        // particleCollision (3 bytes, always written)
        if (self.particle_collision) |pc| {
            try pc.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0 });
        }

        // renderMode
        try buf.append(allocator, @intFromEnum(self.render_mode));

        // lightInfluence
        try writeF32(&buf, allocator, self.light_influence);

        // linearFiltering
        try buf.append(allocator, if (self.linear_filtering) @as(u8, 1) else 0);

        // particleLifeSpan (8 bytes, always written)
        if (self.particle_life_span) |pls| {
            try pls.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // intersectionHighlight (8 bytes, always written)
        if (self.intersection_highlight) |ih| {
            try ih.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // Reserve 4 offset slots (16 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const particle_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const uv_motion_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const attractors_offset_slot = buf.items.len;
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

        // particle
        if (self.particle) |p| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[particle_offset_slot..][0..4], offset, .little);
            try p.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[particle_offset_slot..][0..4], -1, .little);
        }

        // uvMotion
        if (self.uv_motion) |uvm| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[uv_motion_offset_slot..][0..4], offset, .little);
            try uvm.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[uv_motion_offset_slot..][0..4], -1, .little);
        }

        // attractors
        if (self.attractors) |attrs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[attractors_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(attrs.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (attrs) |attr| {
                try attr.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[attractors_offset_slot..][0..4], -1, .little);
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

test "ParticleSpawnerAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = ParticleSpawnerAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 147 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 147), data.len);

    // Check nullBits are 0
    try std.testing.expectEqual(@as(u8, 0), data[0]);
    try std.testing.expectEqual(@as(u8, 0), data[1]);

    // Check offset slots are -1
    const id_offset = std.mem.readInt(i32, data[131..135], .little);
    const particle_offset = std.mem.readInt(i32, data[135..139], .little);
    const uv_motion_offset = std.mem.readInt(i32, data[139..143], .little);
    const attractors_offset = std.mem.readInt(i32, data[143..147], .little);
    try std.testing.expectEqual(@as(i32, -1), id_offset);
    try std.testing.expectEqual(@as(i32, -1), particle_offset);
    try std.testing.expectEqual(@as(i32, -1), uv_motion_offset);
    try std.testing.expectEqual(@as(i32, -1), attractors_offset);
}

test "ParticleSpawnerAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = ParticleSpawnerAsset{
        .id = "fire_spawner",
        .life_span = 10.0,
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed (147) + VarInt(12) + "fire_spawner"
    try std.testing.expectEqual(@as(usize, 147 + 1 + 12), data.len);

    // Check nullBits[1] has id set
    try std.testing.expectEqual(@as(u8, 0x01), data[1]);

    // Check id offset is 0
    const id_offset = std.mem.readInt(i32, data[131..135], .little);
    try std.testing.expectEqual(@as(i32, 0), id_offset);
}

test "ParticleCollision serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const collision = ParticleCollision{
        .block_type = .solid,
        .action = .last_frame,
    };
    try collision.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 3), buf.items.len);
    try std.testing.expectEqual(@as(u8, 2), buf.items[0]); // solid
    try std.testing.expectEqual(@as(u8, 1), buf.items[1]); // last_frame
}

test "IntersectionHighlight serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const highlight = IntersectionHighlight{
        .highlight_threshold = 0.5,
        .highlight_color = .{ .red = 255, .green = 0, .blue = 0 },
    };
    try highlight.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 8), buf.items.len);
    try std.testing.expectEqual(@as(u8, 0x01), buf.items[0]); // nullBits
}

test "Particle serialize minimal" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const particle = Particle{};
    try particle.serialize(&buf, allocator);

    // Fixed 141 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 141), buf.items.len);
}

test "UVMotion serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const uv_motion = UVMotion{
        .speed_x = 1.0,
        .speed_y = 2.0,
    };
    try uv_motion.serialize(&buf, allocator);

    // Fixed 19 bytes (no texture)
    try std.testing.expectEqual(@as(usize, 19), buf.items.len);
}
