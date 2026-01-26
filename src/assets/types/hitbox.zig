/// Hitbox Type
///
/// Represents an axis-aligned bounding box (AABB) for collision.
/// Based on com/hypixel/hytale/protocol/Hitbox.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Hitbox - an axis-aligned bounding box
/// Fixed 24 bytes: 6 x f32 (minX, minY, minZ, maxX, maxY, maxZ)
pub const Hitbox = struct {
    min_x: f32 = 0.0,
    min_y: f32 = 0.0,
    min_z: f32 = 0.0,
    max_x: f32 = 1.0,
    max_y: f32 = 1.0,
    max_z: f32 = 1.0,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 0;
    pub const FIXED_BLOCK_SIZE: u32 = 24;
    pub const VARIABLE_FIELD_COUNT: u32 = 0;
    pub const VARIABLE_BLOCK_START: u32 = 24;

    /// Create a unit cube hitbox (0,0,0 to 1,1,1)
    pub fn unitCube() Self {
        return .{
            .min_x = 0.0,
            .min_y = 0.0,
            .min_z = 0.0,
            .max_x = 1.0,
            .max_y = 1.0,
            .max_z = 1.0,
        };
    }

    /// Create a custom hitbox
    pub fn init(min_x: f32, min_y: f32, min_z: f32, max_x: f32, max_y: f32, max_z: f32) Self {
        return .{
            .min_x = min_x,
            .min_y = min_y,
            .min_z = min_z,
            .max_x = max_x,
            .max_y = max_y,
            .max_z = max_z,
        };
    }

    pub fn serialize(self: *const Self, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.min_x);
        try writeF32(buf, allocator, self.min_y);
        try writeF32(buf, allocator, self.min_z);
        try writeF32(buf, allocator, self.max_x);
        try writeF32(buf, allocator, self.max_y);
        try writeF32(buf, allocator, self.max_z);
    }
};

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

test "Hitbox unit cube" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const hitbox = Hitbox.unitCube();
    try hitbox.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 24), buf.items.len);

    // Check min values are 0
    const min_x = @as(f32, @bitCast(std.mem.readInt(u32, buf.items[0..4], .little)));
    try std.testing.expectEqual(@as(f32, 0.0), min_x);

    // Check max values are 1
    const max_x = @as(f32, @bitCast(std.mem.readInt(u32, buf.items[12..16], .little)));
    try std.testing.expectEqual(@as(f32, 1.0), max_x);
}

test "Hitbox custom values" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const hitbox = Hitbox.init(0.1, 0.2, 0.3, 0.9, 0.8, 0.7);
    try hitbox.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 24), buf.items.len);
}
