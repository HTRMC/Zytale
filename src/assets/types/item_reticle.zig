/// ItemReticle Asset
///
/// Represents item reticle (crosshair) configuration.
/// Based on com/hypixel/hytale/protocol/ItemReticle.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// ItemReticle asset
/// Fixed: 1 (nullBits) + 1 (hideBase) + 4 (duration) = 6 bytes
pub const ItemReticleAsset = struct {
    hide_base: bool = false,
    parts: ?[]const []const u8 = null,
    duration: f32 = 0.0,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 6;
    pub const VARIABLE_FIELD_COUNT: u32 = 1;
    pub const VARIABLE_BLOCK_START: u32 = 6;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.parts != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // hideBase (1 byte)
        try buf.append(allocator, if (self.hide_base) 1 else 0);

        // duration (f32 LE)
        var duration_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &duration_bytes, @bitCast(self.duration), .little);
        try buf.appendSlice(allocator, &duration_bytes);

        // parts array (variable, inline)
        if (self.parts) |parts| {
            try writeVarInt(&buf, allocator, @intCast(parts.len));
            for (parts) |part| {
                try writeVarString(&buf, allocator, part);
            }
        }

        return buf.toOwnedSlice(allocator);
    }
};

// Helper functions
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

test "ItemReticleAsset serialization" {
    const allocator = std.testing.allocator;

    var reticle = ItemReticleAsset{
        .hide_base = true,
        .duration = 0.5,
    };

    const data = try reticle.serialize(allocator);
    defer allocator.free(data);

    // Should produce 6 bytes (fixed only)
    try std.testing.expectEqual(@as(usize, 6), data.len);

    // Check nullBits (no parts)
    try std.testing.expectEqual(@as(u8, 0x00), data[0]);

    // Check hideBase
    try std.testing.expectEqual(@as(u8, 1), data[1]);
}

test "ItemReticleAsset with parts" {
    const allocator = std.testing.allocator;

    const parts = [_][]const u8{ "part1.png", "part2.png" };

    var reticle = ItemReticleAsset{
        .parts = &parts,
    };

    const data = try reticle.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits has parts
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);

    // Should have more than 6 bytes
    try std.testing.expect(data.len > 6);
}
