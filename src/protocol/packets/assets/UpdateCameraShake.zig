/// UpdateCameraShake Packet (ID 77)
///
/// Sends camera shake config definitions to the client.

const std = @import("std");
const serializer = @import("serializer.zig");
const camera_shake = @import("../../../assets/types/camera_shake.zig");

pub const CameraShakeAsset = camera_shake.CameraShakeAsset;
pub const CameraShakeConfig = camera_shake.CameraShakeConfig;

// Constants from Java UpdateCameraShake.java
pub const PACKET_ID: u32 = 77;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// Serialize UpdateCameraShake packet
/// Format:
/// - nullBits (1 byte): bit 0 = cameraShakeConfigs present
/// - type (1 byte): UpdateType enum
/// - If bit 0 set: VarInt count + array of CameraShake
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    configs: []const CameraShakeAsset,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = configs present
    const null_bits: u8 = if (configs.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // configs array (if present)
    if (configs.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(configs.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each config
        for (configs) |*config| {
            const config_data = try config.serialize(allocator);
            defer allocator.free(config_data);
            try buf.appendSlice(allocator, config_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (3 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 3);
    buf[0] = 0x01; // nullBits: array present (but empty)
    buf[1] = 0x00; // type: init
    buf[2] = 0x00; // VarInt: 0 elements
    return buf;
}

test "UpdateCameraShake empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
}

test "UpdateCameraShake with configs" {
    const allocator = std.testing.allocator;

    const configs = [_]CameraShakeAsset{
        .{
            .first_person = .{ .duration = 0.5, .continuous = false },
            .third_person = .{ .duration = 0.3, .continuous = false },
        },
    };

    const pkt = try serialize(allocator, .init, &configs);
    defer allocator.free(pkt);

    // Should have header + 1 config
    try std.testing.expect(pkt.len > 3);

    // Check nullBits has array present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);
}
