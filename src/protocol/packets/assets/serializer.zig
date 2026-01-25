/// Asset Packet Serialization Utilities
///
/// Generic serializers and helpers for Update* packets (IDs 40-85).
/// All asset packets share a common structure with variations in fixed block size.

const std = @import("std");
const common = @import("../../../assets/types/common.zig");
const protocol_serializer = @import("../serializer.zig");

pub const UpdateType = common.UpdateType;

/// Write a VarInt to buffer, returns bytes written
pub fn writeVarInt(buf: []u8, value: u32) usize {
    return protocol_serializer.writeVarInt(buf, value);
}

/// Calculate VarInt size for a value
pub fn varIntSize(value: u32) usize {
    return protocol_serializer.varIntSize(value);
}

/// Write a VarString (VarInt length + UTF-8 bytes)
pub fn writeVarString(allocator: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), str: []const u8) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarInt(&vi_buf, @intCast(str.len));
    try writer.appendSlice(allocator, vi_buf[0..vi_len]);
    try writer.appendSlice(allocator, str);
}

/// Helper to write f32 as little-endian bytes
pub fn writeF32(allocator: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), value: f32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, @bitCast(value), .little);
    try writer.appendSlice(allocator, &buf);
}

/// Helper to write i32 as little-endian bytes
pub fn writeI32(allocator: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), value: i32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, value, .little);
    try writer.appendSlice(allocator, &buf);
}

/// Helper to write f64 as little-endian bytes
pub fn writeF64(allocator: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), value: f64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, @bitCast(value), .little);
    try writer.appendSlice(allocator, &buf);
}

/// Serialize an empty Update* packet (no assets, but with empty dictionary)
/// The client expects a dictionary to always be present, even if empty
///
/// Format: nullBits(1) + type(1) + maxId(4) + extra_fixed_bytes + VarInt(0)
pub fn serializeEmptyUpdate(
    allocator: std.mem.Allocator,
    update_type: UpdateType,
    max_id: i32,
    extra_fixed_bytes: []const u8,
) ![]u8 {
    const total_size = 7 + extra_fixed_bytes.len;
    const buf = try allocator.alloc(u8, total_size);

    buf[0] = 0x01; // nullBits: dictionary IS present (bit 0 = 1)
    buf[1] = @intFromEnum(update_type);
    std.mem.writeInt(i32, buf[2..6], max_id, .little);

    var offset: usize = 6;
    if (extra_fixed_bytes.len > 0) {
        @memcpy(buf[6..][0..extra_fixed_bytes.len], extra_fixed_bytes);
        offset += extra_fixed_bytes.len;
    }

    buf[offset] = 0x00; // VarInt count = 0 (empty dictionary)

    return buf;
}

/// Serialize empty string-keyed Update packet (3 bytes)
/// Used by: UpdateTrails, UpdateItemPlayerAnimations
///
/// Format: nullBits(1) + type(1) + VarInt(0)
pub fn serializeEmptyStringKeyedUpdate(
    allocator: std.mem.Allocator,
    update_type: UpdateType,
) ![]u8 {
    const buf = try allocator.alloc(u8, 3);
    buf[0] = 0x01; // nullBits: dictionary IS present
    buf[1] = @intFromEnum(update_type);
    buf[2] = 0x00; // VarInt count = 0 (empty dictionary)
    return buf;
}

/// Serialize empty Update* packet with NULL dictionary (nullBits=0)
/// Some clients may expect null instead of empty dictionary
///
/// Format: nullBits(1) + type(1) + maxId(4) = 6 bytes (NO VarInt count!)
pub fn serializeNullDictionaryUpdate(
    allocator: std.mem.Allocator,
    update_type: UpdateType,
    max_id: i32,
) ![]u8 {
    const buf = try allocator.alloc(u8, 6);
    buf[0] = 0x00; // nullBits: dictionary is NULL (not present)
    buf[1] = @intFromEnum(update_type);
    std.mem.writeInt(i32, buf[2..6], max_id, .little);
    return buf;
}

/// Generic asset entry serializer for integer-keyed assets
/// The callback receives the entry and should write its data to the writer
pub fn AssetSerializer(comptime EntryType: type) type {
    return struct {
        pub const SerializeFn = *const fn (allocator: std.mem.Allocator, entry: *const EntryType, writer: *std.ArrayListUnmanaged(u8)) anyerror!void;

        pub const IndexedEntry = struct {
            index: u32,
            value: EntryType,
        };

        /// Serialize a map of assets to Update* packet format
        pub fn serialize(
            allocator: std.mem.Allocator,
            update_type: UpdateType,
            max_id: i32,
            entries: []const IndexedEntry,
            extra_fixed_bytes: []const u8,
            serializeEntry: SerializeFn,
        ) ![]u8 {
            var data: std.ArrayListUnmanaged(u8) = .empty;
            errdefer data.deinit(allocator);

            // nullBits - ALWAYS indicate dictionary is present (even if empty)
            try data.append(allocator, 0x01);

            // UpdateType
            try data.append(allocator, @intFromEnum(update_type));

            // maxId (i32 LE)
            var max_id_buf: [4]u8 = undefined;
            std.mem.writeInt(i32, &max_id_buf, max_id, .little);
            try data.appendSlice(allocator, &max_id_buf);

            // Extra fixed bytes (packet-specific)
            if (extra_fixed_bytes.len > 0) {
                try data.appendSlice(allocator, extra_fixed_bytes);
            }

            // ALWAYS write VarInt count (even if 0)
            var count_buf: [5]u8 = undefined;
            const count_len = writeVarInt(&count_buf, @intCast(entries.len));
            try data.appendSlice(allocator, count_buf[0..count_len]);

            // Each entry: index (i32 LE) + serialized data
            for (entries) |entry| {
                var index_buf: [4]u8 = undefined;
                std.mem.writeInt(i32, &index_buf, @intCast(entry.index), .little);
                try data.appendSlice(allocator, &index_buf);

                try serializeEntry(allocator, &entry.value, &data);
            }

            return data.toOwnedSlice(allocator);
        }
    };
}

/// String-keyed asset serializer (no maxId, string keys)
/// Used by: UpdateTrails
///
/// Format: nullBits(1) + type(1) + [VarInt count + (VarString key + serialized asset)*]
pub fn StringKeyedSerializer(comptime EntryType: type) type {
    return struct {
        pub const SerializeFn = *const fn (allocator: std.mem.Allocator, entry: *const EntryType, writer: *std.ArrayListUnmanaged(u8)) anyerror!void;

        pub const StringKeyedEntry = struct {
            key: []const u8,
            value: EntryType,
        };

        /// Serialize a map of assets with string keys to Update* packet format
        pub fn serialize(
            allocator: std.mem.Allocator,
            update_type: UpdateType,
            entries: []const StringKeyedEntry,
            serializeEntry: SerializeFn,
        ) ![]u8 {
            var data: std.ArrayListUnmanaged(u8) = .empty;
            errdefer data.deinit(allocator);

            // nullBits - ALWAYS indicate dictionary is present (even if empty)
            try data.append(allocator, 0x01);

            // UpdateType
            try data.append(allocator, @intFromEnum(update_type));

            // NO maxId for string-keyed packets!

            // ALWAYS write VarInt count (even if 0)
            var count_buf: [5]u8 = undefined;
            const count_len = writeVarInt(&count_buf, @intCast(entries.len));
            try data.appendSlice(allocator, count_buf[0..count_len]);

            // Each entry: VarString key + serialized data
            for (entries) |entry| {
                try writeVarString(allocator, &data, entry.key);
                try serializeEntry(allocator, &entry.value, &data);
            }

            return data.toOwnedSlice(allocator);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "empty update packet - basic" {
    const allocator = std.testing.allocator;

    const pkt = try serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
    defer allocator.free(pkt);

    try std.testing.expectEqual(@as(usize, 7), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: dictionary present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0x00), pkt[6]); // VarInt count = 0 (empty dictionary)
}

test "empty string-keyed update packet" {
    const allocator = std.testing.allocator;

    const pkt = try serializeEmptyStringKeyedUpdate(allocator, .init);
    defer allocator.free(pkt);

    try std.testing.expectEqual(@as(usize, 3), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: dictionary present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[2]); // VarInt count = 0
}
