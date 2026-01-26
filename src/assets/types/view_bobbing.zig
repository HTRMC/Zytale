/// ViewBobbing Asset
///
/// Represents view bobbing configuration (first person camera movement while walking).
/// Based on com/hypixel/hytale/protocol/ViewBobbing.java

const std = @import("std");
const Allocator = std.mem.Allocator;
const camera_shake = @import("camera_shake.zig");

pub const CameraShakeConfig = camera_shake.CameraShakeConfig;

/// ViewBobbing asset
/// Format: 1 byte nullBits + optional CameraShakeConfig
pub const ViewBobbingAsset = struct {
    first_person: ?CameraShakeConfig = null,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 1;
    pub const VARIABLE_FIELD_COUNT: u32 = 1;
    pub const VARIABLE_BLOCK_START: u32 = 1;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.first_person != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // Write firstPerson config inline (not offset-based for this type)
        if (self.first_person) |*fp| {
            try fp.serialize(&buf, allocator);
        }

        return buf.toOwnedSlice(allocator);
    }
};

test "ViewBobbingAsset empty serialization" {
    const allocator = std.testing.allocator;

    var bobbing = ViewBobbingAsset{};
    const data = try bobbing.serialize(allocator);
    defer allocator.free(data);

    // Should produce 1 byte (just nullBits)
    try std.testing.expectEqual(@as(usize, 1), data.len);

    // Check nullBits is 0
    try std.testing.expectEqual(@as(u8, 0x00), data[0]);
}

test "ViewBobbingAsset with first person" {
    const allocator = std.testing.allocator;

    var bobbing = ViewBobbingAsset{
        .first_person = .{
            .duration = 0.5,
            .continuous = true,
        },
    };

    const data = try bobbing.serialize(allocator);
    defer allocator.free(data);

    // Should have more than 1 byte
    try std.testing.expect(data.len > 1);

    // Check nullBits has firstPerson
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);
}
