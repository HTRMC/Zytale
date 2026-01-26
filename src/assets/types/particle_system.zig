/// ParticleSystem Asset Type
///
/// Represents particle systems with spawner groups.

const std = @import("std");
const entity_stat_type = @import("entity_stat_type.zig");
const Allocator = std.mem.Allocator;

// Re-export Vector3f and Direction
pub const Vector3f = entity_stat_type.Vector3f;
pub const Direction = entity_stat_type.Direction;

/// Float range (8 bytes)
pub const Rangef = struct {
    min: f32 = 0.0,
    max: f32 = 0.0,

    pub fn serialize(self: Rangef, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.min);
        try writeF32(buf, allocator, self.max);
    }
};

/// Initial velocity (25 bytes)
pub const InitialVelocity = struct {
    yaw: ?Rangef = null,
    pitch: ?Rangef = null,
    speed: ?Rangef = null,

    pub const SIZE: usize = 25;

    pub fn serialize(self: InitialVelocity, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.yaw != null) null_bits |= 0x01;
        if (self.pitch != null) null_bits |= 0x02;
        if (self.speed != null) null_bits |= 0x04;
        try buf.append(allocator, null_bits);

        // yaw (8 bytes, always written)
        if (self.yaw) |y| {
            try y.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // pitch (8 bytes, always written)
        if (self.pitch) |p| {
            try p.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // speed (8 bytes, always written)
        if (self.speed) |s| {
            try s.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }
    }
};

/// Range vector 3D (25 bytes)
pub const RangeVector3f = struct {
    x: ?Rangef = null,
    y: ?Rangef = null,
    z: ?Rangef = null,

    pub const SIZE: usize = 25;

    pub fn serialize(self: RangeVector3f, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.x != null) null_bits |= 0x01;
        if (self.y != null) null_bits |= 0x02;
        if (self.z != null) null_bits |= 0x04;
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

        // z (8 bytes, always written)
        if (self.z) |zv| {
            try zv.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }
    }
};

/// Particle attractor (85 bytes fixed)
pub const ParticleAttractor = struct {
    position: ?Vector3f = null,
    radial_axis: ?Vector3f = null,
    trail_position_multiplier: f32 = 0.0,
    radius: f32 = 0.0,
    radial_acceleration: f32 = 0.0,
    radial_tangent_acceleration: f32 = 0.0,
    linear_acceleration: ?Vector3f = null,
    radial_impulse: f32 = 0.0,
    radial_tangent_impulse: f32 = 0.0,
    linear_impulse: ?Vector3f = null,
    damping_multiplier: ?Vector3f = null,

    pub const SIZE: usize = 85;

    pub fn serialize(self: ParticleAttractor, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.position != null) null_bits |= 0x01;
        if (self.radial_axis != null) null_bits |= 0x02;
        if (self.linear_acceleration != null) null_bits |= 0x04;
        if (self.linear_impulse != null) null_bits |= 0x08;
        if (self.damping_multiplier != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // position (12 bytes, always written)
        if (self.position) |p| {
            try p.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // radialAxis (12 bytes, always written)
        if (self.radial_axis) |ra| {
            try ra.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // trailPositionMultiplier
        try writeF32(buf, allocator, self.trail_position_multiplier);
        // radius
        try writeF32(buf, allocator, self.radius);
        // radialAcceleration
        try writeF32(buf, allocator, self.radial_acceleration);
        // radialTangentAcceleration
        try writeF32(buf, allocator, self.radial_tangent_acceleration);

        // linearAcceleration (12 bytes, always written)
        if (self.linear_acceleration) |la| {
            try la.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // radialImpulse
        try writeF32(buf, allocator, self.radial_impulse);
        // radialTangentImpulse
        try writeF32(buf, allocator, self.radial_tangent_impulse);

        // linearImpulse (12 bytes, always written)
        if (self.linear_impulse) |li| {
            try li.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // dampingMultiplier (12 bytes, always written)
        if (self.damping_multiplier) |dm| {
            try dm.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }
    }
};

/// Particle spawner group (121 bytes fixed + variable)
pub const ParticleSpawnerGroup = struct {
    spawner_id: ?[]const u8 = null,
    position_offset: ?Vector3f = null,
    rotation_offset: ?Direction = null,
    fixed_rotation: bool = false,
    start_delay: f32 = 0.0,
    spawn_rate: ?Rangef = null,
    wave_delay: ?Rangef = null,
    total_spawners: i32 = 0,
    max_concurrent: i32 = 0,
    initial_velocity: ?InitialVelocity = null,
    emit_offset: ?RangeVector3f = null,
    life_span: ?Rangef = null,
    attractors: ?[]const ParticleAttractor = null,

    pub const FIXED_BLOCK_SIZE: u32 = 113;
    pub const VARIABLE_BLOCK_START: u32 = 121;

    pub fn serialize(self: ParticleSpawnerGroup, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits (2 bytes)
        var null_bits: [2]u8 = .{ 0, 0 };
        if (self.position_offset != null) null_bits[0] |= 0x01;
        if (self.rotation_offset != null) null_bits[0] |= 0x02;
        if (self.spawn_rate != null) null_bits[0] |= 0x04;
        if (self.wave_delay != null) null_bits[0] |= 0x08;
        if (self.initial_velocity != null) null_bits[0] |= 0x10;
        if (self.emit_offset != null) null_bits[0] |= 0x20;
        if (self.life_span != null) null_bits[0] |= 0x40;
        if (self.spawner_id != null) null_bits[0] |= 0x80;
        if (self.attractors != null) null_bits[1] |= 0x01;
        try buf.appendSlice(allocator, &null_bits);

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

        // fixedRotation
        try buf.append(allocator, if (self.fixed_rotation) @as(u8, 1) else 0);

        // startDelay
        try writeF32(buf, allocator, self.start_delay);

        // spawnRate (8 bytes, always written)
        if (self.spawn_rate) |sr| {
            try sr.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // waveDelay (8 bytes, always written)
        if (self.wave_delay) |wd| {
            try wd.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // totalSpawners
        try writeI32(buf, allocator, self.total_spawners);

        // maxConcurrent
        try writeI32(buf, allocator, self.max_concurrent);

        // initialVelocity (25 bytes, always written)
        if (self.initial_velocity) |iv| {
            try iv.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 25);
        }

        // emitOffset (25 bytes, always written)
        if (self.emit_offset) |eo| {
            try eo.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 25);
        }

        // lifeSpan (8 bytes, always written)
        if (self.life_span) |ls| {
            try ls.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // Reserve 2 offset slots (8 bytes)
        const spawner_id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const attractors_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // spawnerId
        if (self.spawner_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[spawner_id_offset_slot..][0..4], offset, .little);
            try writeVarString(buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[spawner_id_offset_slot..][0..4], -1, .little);
        }

        // attractors
        if (self.attractors) |attrs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[attractors_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(attrs.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (attrs) |attr| {
                try attr.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[attractors_offset_slot..][0..4], -1, .little);
        }
    }
};

/// ParticleSystem asset (22 bytes fixed + variable)
pub const ParticleSystemAsset = struct {
    id: ?[]const u8 = null,
    spawners: ?[]const ParticleSpawnerGroup = null,
    life_span: f32 = 0.0,
    cull_distance: f32 = 0.0,
    bounding_radius: f32 = 0.0,
    is_important: bool = false,

    const Self = @This();

    pub const FIXED_BLOCK_SIZE: u32 = 14;
    pub const VARIABLE_BLOCK_START: u32 = 22;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.spawners != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // lifeSpan
        try writeF32(&buf, allocator, self.life_span);

        // cullDistance
        try writeF32(&buf, allocator, self.cull_distance);

        // boundingRadius
        try writeF32(&buf, allocator, self.bounding_radius);

        // isImportant
        try buf.append(allocator, if (self.is_important) @as(u8, 1) else 0);

        // Reserve 2 offset slots (8 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const spawners_offset_slot = buf.items.len;
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

        // spawners
        if (self.spawners) |spwns| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[spawners_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(spwns.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (spwns) |spwn| {
                try spwn.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[spawners_offset_slot..][0..4], -1, .little);
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

test "ParticleSystemAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = ParticleSystemAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 22 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 22), data.len);

    // Check nullBits is 0 (nothing set)
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check offset slots are -1
    const id_offset = std.mem.readInt(i32, data[14..18], .little);
    const spawners_offset = std.mem.readInt(i32, data[18..22], .little);
    try std.testing.expectEqual(@as(i32, -1), id_offset);
    try std.testing.expectEqual(@as(i32, -1), spawners_offset);
}

test "ParticleSystemAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = ParticleSystemAsset{
        .id = "fire_particles",
        .life_span = 5.0,
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed (22) + VarInt(14) + "fire_particles"
    try std.testing.expectEqual(@as(usize, 22 + 1 + 14), data.len);

    // Check nullBits has id set
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);

    // Check id offset is 0
    const id_offset = std.mem.readInt(i32, data[14..18], .little);
    try std.testing.expectEqual(@as(i32, 0), id_offset);
}

test "ParticleSpawnerGroup serialize minimal" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const group = ParticleSpawnerGroup{};
    try group.serialize(&buf, allocator);

    // Fixed block = 121 bytes
    try std.testing.expectEqual(@as(usize, 121), buf.items.len);
}

test "ParticleAttractor serialize" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const attractor = ParticleAttractor{ .radius = 5.0 };
    try attractor.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 85), buf.items.len);
}
