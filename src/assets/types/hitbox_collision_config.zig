/// HitboxCollisionConfig Asset
///
/// Represents collision configuration for hitboxes.
/// Based on com/hypixel/hytale/protocol/HitboxCollisionConfig.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// CollisionType enum
pub const CollisionType = enum(u8) {
    hard = 0,
    soft = 1,
};

/// HitboxCollisionConfig - 5 bytes fixed, no variable fields
pub const HitboxCollisionConfigAsset = struct {
    collision_type: CollisionType = .hard,
    soft_collision_offset_ratio: f32 = 0.0,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 0;
    pub const FIXED_BLOCK_SIZE: u32 = 5;
    pub const VARIABLE_FIELD_COUNT: u32 = 0;
    pub const VARIABLE_BLOCK_START: u32 = 5;

    pub fn serialize(self: *const Self, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // collisionType (1 byte)
        try buf.append(allocator, @intFromEnum(self.collision_type));

        // softCollisionOffsetRatio (4 bytes f32 LE)
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, @bitCast(self.soft_collision_offset_ratio), .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

test "HitboxCollisionConfigAsset serialization" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const config = HitboxCollisionConfigAsset{
        .collision_type = .soft,
        .soft_collision_offset_ratio = 0.5,
    };
    try config.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 5), buf.items.len);

    // Check collision type = soft (1)
    try std.testing.expectEqual(@as(u8, 1), buf.items[0]);
}

test "HitboxCollisionConfigAsset default" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const config = HitboxCollisionConfigAsset{};
    try config.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 5), buf.items.len);

    // Check collision type = hard (0)
    try std.testing.expectEqual(@as(u8, 0), buf.items[0]);
}
