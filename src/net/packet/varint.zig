const std = @import("std");

/// VarInt encoding (LEB128 variant used by Hytale)
/// - 7 bits of data per byte
/// - MSB set means more bytes follow
/// - Max 5 bytes for 32-bit values

pub const VarIntError = error{
    Overflow,
    EndOfStream,
};

/// Read a VarInt from a byte slice
/// Returns the value and number of bytes consumed
pub fn readVarInt(data: []const u8) VarIntError!struct { value: u32, bytes_read: usize } {
    var value: u32 = 0;
    var shift: u5 = 0;
    var bytes_read: usize = 0;

    for (data) |byte| {
        bytes_read += 1;

        // Extract 7 bits of data
        const segment: u32 = @as(u32, byte & 0x7F);

        // Check for overflow before shifting
        if (shift >= 32) {
            return VarIntError.Overflow;
        }

        value |= segment << shift;
        shift += 7;

        // If MSB is not set, we're done
        if (byte & 0x80 == 0) {
            return .{ .value = value, .bytes_read = bytes_read };
        }

        // Max 5 bytes for 32-bit value
        if (bytes_read >= 5) {
            return VarIntError.Overflow;
        }
    }

    return VarIntError.EndOfStream;
}

/// Write a VarInt to a buffer
/// Returns number of bytes written
pub fn writeVarInt(value: u32, buf: []u8) usize {
    var v = value;
    var idx: usize = 0;

    while (v >= 0x80) {
        buf[idx] = @as(u8, @truncate(v)) | 0x80;
        v >>= 7;
        idx += 1;
    }

    buf[idx] = @as(u8, @truncate(v));
    return idx + 1;
}

/// Calculate how many bytes a VarInt would take
pub fn varIntSize(value: u32) usize {
    if (value < 0x80) return 1;
    if (value < 0x4000) return 2;
    if (value < 0x200000) return 3;
    if (value < 0x10000000) return 4;
    return 5;
}

/// Read a VarInt-prefixed string
pub fn readVarString(allocator: std.mem.Allocator, data: []const u8) !struct { value: []u8, bytes_read: usize } {
    const len_result = try readVarInt(data);
    const str_start = len_result.bytes_read;
    const str_len = len_result.value;

    if (data.len < str_start + str_len) {
        return VarIntError.EndOfStream;
    }

    const str = try allocator.alloc(u8, str_len);
    @memcpy(str, data[str_start .. str_start + str_len]);

    return .{
        .value = str,
        .bytes_read = str_start + str_len,
    };
}

/// Write a VarInt-prefixed string
pub fn writeVarString(str: []const u8, buf: []u8) usize {
    const len_bytes = writeVarInt(@intCast(str.len), buf);
    @memcpy(buf[len_bytes .. len_bytes + str.len], str);
    return len_bytes + str.len;
}

// Tests
test "varint encode/decode small values" {
    var buf: [5]u8 = undefined;

    // Single byte values (0-127)
    {
        const written = writeVarInt(0, &buf);
        try std.testing.expectEqual(@as(usize, 1), written);
        try std.testing.expectEqual(@as(u8, 0), buf[0]);

        const result = try readVarInt(&buf);
        try std.testing.expectEqual(@as(u32, 0), result.value);
        try std.testing.expectEqual(@as(usize, 1), result.bytes_read);
    }

    {
        const written = writeVarInt(127, &buf);
        try std.testing.expectEqual(@as(usize, 1), written);
        try std.testing.expectEqual(@as(u8, 127), buf[0]);

        const result = try readVarInt(&buf);
        try std.testing.expectEqual(@as(u32, 127), result.value);
    }
}

test "varint encode/decode multi-byte values" {
    var buf: [5]u8 = undefined;

    // 128 = 0x80 -> needs 2 bytes
    {
        const written = writeVarInt(128, &buf);
        try std.testing.expectEqual(@as(usize, 2), written);
        try std.testing.expectEqual(@as(u8, 0x80), buf[0]); // 0 | 0x80
        try std.testing.expectEqual(@as(u8, 0x01), buf[1]); // 1

        const result = try readVarInt(&buf);
        try std.testing.expectEqual(@as(u32, 128), result.value);
        try std.testing.expectEqual(@as(usize, 2), result.bytes_read);
    }

    // 300 = 0x12C -> needs 2 bytes
    {
        const written = writeVarInt(300, &buf);
        try std.testing.expectEqual(@as(usize, 2), written);

        const result = try readVarInt(&buf);
        try std.testing.expectEqual(@as(u32, 300), result.value);
    }

    // Max u32 value
    {
        const written = writeVarInt(0xFFFFFFFF, &buf);
        try std.testing.expectEqual(@as(usize, 5), written);

        const result = try readVarInt(&buf);
        try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), result.value);
    }
}

test "varint size calculation" {
    try std.testing.expectEqual(@as(usize, 1), varIntSize(0));
    try std.testing.expectEqual(@as(usize, 1), varIntSize(127));
    try std.testing.expectEqual(@as(usize, 2), varIntSize(128));
    try std.testing.expectEqual(@as(usize, 2), varIntSize(16383));
    try std.testing.expectEqual(@as(usize, 3), varIntSize(16384));
    try std.testing.expectEqual(@as(usize, 5), varIntSize(0xFFFFFFFF));
}
