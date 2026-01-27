/// UpdateWeathers Packet (ID 47)
///
/// Sends weather definitions to the client.
/// Uses int-keyed dictionary with inline variable fields.

const std = @import("std");
const serializer = @import("serializer.zig");
const weather = @import("../../../assets/types/weather.zig");

pub const WeatherAsset = weather.WeatherAsset;

// Constants from Java UpdateWeathers.java
pub const PACKET_ID: u32 = 47;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// Weather entry for serialization (int-keyed)
pub const WeatherEntry = struct {
    id: i32,
    weather: WeatherAsset,
};

/// Serialize UpdateWeathers packet
/// Format (int-keyed dictionary, inline variable):
/// - nullBits (1 byte): bit 0 = weathers present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes): i32 LE
/// - Inline variable: VarInt count + entries (key i32 + Weather data)
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: ?[]const WeatherEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits - matches Java: checks != null, not size > 0
    var null_bits: u8 = 0;
    if (entries != null) null_bits |= 0x01;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, max_id, .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // weathers (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + Weather data
        for (ents) |entry| {
            // Key
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, entry.id, .little);
            try buf.appendSlice(allocator, &key_bytes);

            // Weather data
            const weather_data = try entry.weather.serialize(allocator);
            defer allocator.free(weather_data);
            try buf.appendSlice(allocator, weather_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateWeathers empty packet size" {
    const allocator = std.testing.allocator;
    // Call serialize with null like Java
    const pkt = try serialize(allocator, .init, 0, null);
    defer allocator.free(pkt);
    // Null dictionary: nullBits(1) + type(1) + maxId(4) = 6 bytes
    try std.testing.expectEqual(@as(usize, 6), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x00), pkt[0]); // nullBits = 0 (null)
}

test "UpdateWeathers with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]WeatherEntry{
        .{ .id = 1, .weather = .{ .id = "clear" } },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Check nullBits has weathers present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check maxId is 1
    const max_id = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 1), max_id);

    // Check count is 1
    try std.testing.expectEqual(@as(u8, 1), pkt[6]);

    // Check key is 1
    const key = std.mem.readInt(i32, pkt[7..11], .little);
    try std.testing.expectEqual(@as(i32, 1), key);
}
