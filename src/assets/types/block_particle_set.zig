/// BlockParticleSet Asset
///
/// Represents a set of particles for block interactions.
/// Based on com/hypixel/hytale/protocol/BlockParticleSet.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Color (RGB, 3 bytes)
pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    pub fn serialize(self: *const Color, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.r);
        try buf.append(allocator, self.g);
        try buf.append(allocator, self.b);
    }
};

/// Vector3f (12 bytes)
pub const Vector3f = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn serialize(self: *const Vector3f, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.x);
        try writeF32(buf, allocator, self.y);
        try writeF32(buf, allocator, self.z);
    }
};

/// Direction (yaw/pitch/roll, 12 bytes)
pub const Direction = struct {
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    roll: f32 = 0.0,

    pub fn serialize(self: *const Direction, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.yaw);
        try writeF32(buf, allocator, self.pitch);
        try writeF32(buf, allocator, self.roll);
    }
};

/// Block particle event types
pub const BlockParticleEvent = enum(u8) {
    walk = 0,
    run = 1,
    sprint = 2,
    soft_land = 3,
    hard_land = 4,
    move_out = 5,
    hit = 6,
    break_block = 7,
    build = 8,
    physics = 9,
};

/// Particle system entry (maps BlockParticleEvent -> particle system id string)
pub const ParticleSystemIdEntry = struct {
    event: BlockParticleEvent,
    particle_system_id: []const u8,
};

/// BlockParticleSet asset
/// Fixed: 1 (nullBits) + 3 (color) + 4 (scale) + 12 (positionOffset) + 12 (rotationOffset) + 8 (offset slots) = 40 bytes
pub const BlockParticleSetAsset = struct {
    id: ?[]const u8 = null,
    color: ?Color = null,
    scale: f32 = 1.0,
    position_offset: ?Vector3f = null,
    rotation_offset: ?Direction = null,
    particle_system_ids: ?[]const ParticleSystemIdEntry = null,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 32;
    pub const VARIABLE_FIELD_COUNT: u32 = 2;
    pub const VARIABLE_BLOCK_START: u32 = 40;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.color != null) null_bits |= 0x01;
        if (self.position_offset != null) null_bits |= 0x02;
        if (self.rotation_offset != null) null_bits |= 0x04;
        if (self.id != null) null_bits |= 0x08;
        if (self.particle_system_ids != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // color (3 bytes) or zeros
        if (self.color) |*c| {
            try c.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 3);
        }

        // scale (4 bytes)
        try writeF32(&buf, allocator, self.scale);

        // positionOffset (12 bytes) or zeros
        if (self.position_offset) |*pos| {
            try pos.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 12);
        }

        // rotationOffset (12 bytes) or zeros
        if (self.rotation_offset) |*rot| {
            try rot.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 12);
        }

        // Offset slots (2 x 4 bytes = 8 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const particle_system_ids_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        // Write id string
        if (self.id) |id_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id_str);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], -1, .little);
        }

        // Write particleSystemIds dictionary
        if (self.particle_system_ids) |ids| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[particle_system_ids_offset_pos..][0..4], offset, .little);

            // VarInt count
            try writeVarInt(&buf, allocator, @intCast(ids.len));

            // Each entry: u8 key + VarString value
            for (ids) |entry| {
                try buf.append(allocator, @intFromEnum(entry.event));
                try writeVarString(&buf, allocator, entry.particle_system_id);
            }
        } else {
            std.mem.writeInt(i32, buf.items[particle_system_ids_offset_pos..][0..4], -1, .little);
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

test "BlockParticleSetAsset serialization" {
    const allocator = std.testing.allocator;

    var particle_set = BlockParticleSetAsset{
        .id = "grass_particles",
        .scale = 1.5,
    };

    const data = try particle_set.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 40 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 40);

    // Check nullBits: id set (0x08)
    try std.testing.expectEqual(@as(u8, 0x08), data[0]);
}

test "BlockParticleSetAsset with all fields" {
    const allocator = std.testing.allocator;

    const ids = [_]ParticleSystemIdEntry{
        .{ .event = .walk, .particle_system_id = "dust_walk" },
        .{ .event = .break_block, .particle_system_id = "dust_break" },
    };

    var particle_set = BlockParticleSetAsset{
        .id = "stone_particles",
        .color = .{ .r = 128, .g = 128, .b = 128 },
        .scale = 1.0,
        .position_offset = .{ .x = 0.0, .y = 0.5, .z = 0.0 },
        .particle_system_ids = &ids,
    };

    const data = try particle_set.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits: color (0x01) + positionOffset (0x02) + id (0x08) + particleSystemIds (0x10) = 0x1B
    try std.testing.expectEqual(@as(u8, 0x1B), data[0]);
}
