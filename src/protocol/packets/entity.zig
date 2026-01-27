const std = @import("std");
const varint = @import("../../net/packet/varint.zig");

/// Entity update types
pub const EntityUpdateType = enum(u8) {
    /// Add a new entity
    add = 0,
    /// Update existing entity
    update = 1,
    /// Remove an entity
    remove = 2,
};

/// Entity types
pub const EntityType = enum(u16) {
    player = 0,
    npc = 1,
    item = 2,
    projectile = 3,
    // ... many more entity types
    _,
};

/// 3D Vector (f32)
pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn write(self: Vec3, buf: []u8) void {
        @memcpy(buf[0..4], &@as([4]u8, @bitCast(self.x)));
        @memcpy(buf[4..8], &@as([4]u8, @bitCast(self.y)));
        @memcpy(buf[8..12], &@as([4]u8, @bitCast(self.z)));
    }
};

/// Quaternion rotation (f32)
pub const Quat = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn identity() Quat {
        return .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    }

    pub fn write(self: Quat, buf: []u8) void {
        @memcpy(buf[0..4], &@as([4]u8, @bitCast(self.x)));
        @memcpy(buf[4..8], &@as([4]u8, @bitCast(self.y)));
        @memcpy(buf[8..12], &@as([4]u8, @bitCast(self.z)));
        @memcpy(buf[12..16], &@as([4]u8, @bitCast(self.w)));
    }
};

/// Entity data for network transmission
pub const EntityData = struct {
    entity_id: u32,
    entity_type: EntityType,
    position: Vec3,
    rotation: Quat,
    velocity: Vec3,

    /// Serialize entity data
    /// This is a simplified format - full format has many more fields
    pub fn serialize(self: *const EntityData, allocator: std.mem.Allocator) ![]u8 {
        // Minimal entity data:
        // [4 bytes] entity_id
        // [2 bytes] entity_type
        // [12 bytes] position (Vec3)
        // [16 bytes] rotation (Quat)
        // [12 bytes] velocity (Vec3)
        const size: usize = 46;
        const buf = try allocator.alloc(u8, size);
        errdefer allocator.free(buf);

        var offset: usize = 0;

        // Entity ID
        std.mem.writeInt(u32, buf[offset..][0..4], self.entity_id, .little);
        offset += 4;

        // Entity type
        std.mem.writeInt(u16, buf[offset..][0..2], @intFromEnum(self.entity_type), .little);
        offset += 2;

        // Position
        self.position.write(buf[offset..][0..12]);
        offset += 12;

        // Rotation
        self.rotation.write(buf[offset..][0..16]);
        offset += 16;

        // Velocity
        self.velocity.write(buf[offset..][0..12]);
        offset += 12;

        return buf;
    }
};

/// EntityUpdates packet (ID=161)
/// Sends entity state changes to clients (compressed)
///
/// Format:
/// [VarInt] update count
/// For each update:
///   [1 byte] update type (add/update/remove)
///   [entity data] varies by type
pub const EntityUpdates = struct {
    allocator: std.mem.Allocator,
    updates: std.ArrayListUnmanaged(EntityUpdate),

    pub const EntityUpdate = struct {
        update_type: EntityUpdateType,
        entity_id: u32,
        data: ?EntityData,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .updates = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.updates.deinit(self.allocator);
    }

    /// Add a new entity
    pub fn addEntity(self: *Self, data: EntityData) !void {
        try self.updates.append(self.allocator, .{
            .update_type = .add,
            .entity_id = data.entity_id,
            .data = data,
        });
    }

    /// Update an existing entity
    pub fn updateEntity(self: *Self, data: EntityData) !void {
        try self.updates.append(self.allocator, .{
            .update_type = .update,
            .entity_id = data.entity_id,
            .data = data,
        });
    }

    /// Remove an entity
    pub fn removeEntity(self: *Self, entity_id: u32) !void {
        try self.updates.append(self.allocator, .{
            .update_type = .remove,
            .entity_id = entity_id,
            .data = null,
        });
    }

    /// Serialize all updates
    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        // Calculate total size
        var total_size: usize = varint.varIntSize(@intCast(self.updates.items.len));

        for (self.updates.items) |update| {
            total_size += 1; // update type
            total_size += 4; // entity id

            if (update.data) |_| {
                total_size += 46; // entity data size
            }
        }

        const buf = try allocator.alloc(u8, total_size);
        errdefer allocator.free(buf);

        var offset: usize = 0;

        // Write update count
        offset += varint.writeVarInt(@intCast(self.updates.items.len), buf[offset..]);

        // Write each update
        for (self.updates.items) |update| {
            buf[offset] = @intFromEnum(update.update_type);
            offset += 1;

            std.mem.writeInt(u32, buf[offset..][0..4], update.entity_id, .little);
            offset += 4;

            if (update.data) |data| {
                const entity_data = try data.serialize(allocator);
                defer allocator.free(entity_data);
                @memcpy(buf[offset .. offset + entity_data.len], entity_data);
                offset += entity_data.len;
            }
        }

        return buf[0..offset];
    }

    /// Create packet with player spawn at given position
    pub fn spawnPlayer(allocator: std.mem.Allocator, entity_id: u32, x: f32, y: f32, z: f32) !Self {
        var updates = Self.init(allocator);
        errdefer updates.deinit();

        try updates.addEntity(.{
            .entity_id = entity_id,
            .entity_type = .player,
            .position = .{ .x = x, .y = y, .z = z },
            .rotation = Quat.identity(),
            .velocity = .{ .x = 0, .y = 0, .z = 0 },
        });

        return updates;
    }
};

test "vec3 write" {
    var buf: [12]u8 = undefined;
    const vec = Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    vec.write(&buf);

    try std.testing.expectEqual(@as(f32, 1.0), @as(f32, @bitCast(buf[0..4].*)));
    try std.testing.expectEqual(@as(f32, 2.0), @as(f32, @bitCast(buf[4..8].*)));
    try std.testing.expectEqual(@as(f32, 3.0), @as(f32, @bitCast(buf[8..12].*)));
}

test "entity updates serialization" {
    const allocator = std.testing.allocator;

    var updates = EntityUpdates.init(allocator);
    defer updates.deinit();

    try updates.addEntity(.{
        .entity_id = 1,
        .entity_type = .player,
        .position = .{ .x = 0, .y = 81, .z = 0 },
        .rotation = Quat.identity(),
        .velocity = .{ .x = 0, .y = 0, .z = 0 },
    });

    const data = try updates.serialize(allocator);
    defer allocator.free(data);

    // Should have: varint(1) + type(1) + id(4) + entity_data(46)
    try std.testing.expect(data.len > 0);

    // First byte is varint count = 1
    try std.testing.expectEqual(@as(u8, 1), data[0]);
}

test "spawn player" {
    const allocator = std.testing.allocator;

    var updates = try EntityUpdates.spawnPlayer(allocator, 123, 0, 81, 0);
    defer updates.deinit();

    try std.testing.expectEqual(@as(usize, 1), updates.updates.items.len);
    try std.testing.expectEqual(EntityUpdateType.add, updates.updates.items[0].update_type);
    try std.testing.expectEqual(@as(u32, 123), updates.updates.items[0].entity_id);
}
