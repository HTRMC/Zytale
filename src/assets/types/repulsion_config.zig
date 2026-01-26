/// RepulsionConfig Asset
///
/// Represents repulsion force configuration.
/// Based on com/hypixel/hytale/protocol/RepulsionConfig.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// RepulsionConfig - 12 bytes fixed, no variable fields
pub const RepulsionConfigAsset = struct {
    radius: f32 = 0.0,
    min_force: f32 = 0.0,
    max_force: f32 = 0.0,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 0;
    pub const FIXED_BLOCK_SIZE: u32 = 12;
    pub const VARIABLE_FIELD_COUNT: u32 = 0;
    pub const VARIABLE_BLOCK_START: u32 = 12;

    pub fn serialize(self: *const Self, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // radius (4 bytes f32 LE)
        try writeF32(buf, allocator, self.radius);

        // minForce (4 bytes f32 LE)
        try writeF32(buf, allocator, self.min_force);

        // maxForce (4 bytes f32 LE)
        try writeF32(buf, allocator, self.max_force);
    }
};

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

test "RepulsionConfigAsset serialization" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const config = RepulsionConfigAsset{
        .radius = 1.0,
        .min_force = 0.5,
        .max_force = 2.0,
    };
    try config.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 12), buf.items.len);

    // Check radius = 1.0
    const radius: f32 = @bitCast(std.mem.readInt(u32, buf.items[0..4], .little));
    try std.testing.expectEqual(@as(f32, 1.0), radius);
}

test "RepulsionConfigAsset default" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const config = RepulsionConfigAsset{};
    try config.serialize(&buf, allocator);

    try std.testing.expectEqual(@as(usize, 12), buf.items.len);
}
