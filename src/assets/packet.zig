/// Asset Update Packet Serialization
///
/// Handles serialization of Update* packets (IDs 40-85) for sending asset data to clients.
/// All these packets share a common structure:
///
/// [1 byte]  nullBits - which optional fields are present
/// [1 byte]  UpdateType (0=Init, 1=AddOrUpdate, 2=Remove)
/// [4 bytes] maxId (i32 LE) - next available index
/// [1 byte]  extra fixed fields (depends on packet type)
/// [VarInt]  count - number of entries (if nullBits & 1)
/// [entries] index (i32 LE) + serialized asset data

const std = @import("std");
const common = @import("types/common.zig");
const serializer = @import("../protocol/packets/serializer.zig");

const UpdateType = common.UpdateType;

/// Write a VarInt to buffer, returns bytes written
pub fn writeVarInt(buf: []u8, value: u32) usize {
    return serializer.writeVarInt(buf, value);
}

/// Calculate VarInt size for a value
pub fn varIntSize(value: u32) usize {
    return serializer.varIntSize(value);
}

/// Write a VarString (VarInt length + UTF-8 bytes)
pub fn writeVarString(allocator: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), str: []const u8) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarInt(&vi_buf, @intCast(str.len));
    try writer.appendSlice(allocator, vi_buf[0..vi_len]);
    try writer.appendSlice(allocator, str);
}

/// Serialize an empty Update* packet (no assets)
/// This is used when we have no assets of a particular type
pub fn serializeEmptyUpdate(
    allocator: std.mem.Allocator,
    update_type: UpdateType,
    max_id: i32,
    extra_fixed_bytes: []const u8,
) ![]u8 {
    // Size: nullBits(1) + type(1) + maxId(4) + extra + no entries
    const total_size = 6 + extra_fixed_bytes.len;
    const buf = try allocator.alloc(u8, total_size);

    buf[0] = 0x00; // nullBits: no optional fields (no entries)
    buf[1] = @intFromEnum(update_type);
    std.mem.writeInt(i32, buf[2..6], max_id, .little);

    if (extra_fixed_bytes.len > 0) {
        @memcpy(buf[6..], extra_fixed_bytes);
    }

    return buf;
}

/// Generic asset entry serializer
/// The callback receives the entry and should write its data to the writer
pub fn AssetSerializer(comptime EntryType: type) type {
    return struct {
        pub const SerializeFn = *const fn (allocator: std.mem.Allocator, entry: *const EntryType, writer: *std.ArrayListUnmanaged(u8)) anyerror!void;

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

            // nullBits
            const null_bits: u8 = if (entries.len > 0) 0x01 else 0x00;
            try data.append(allocator, null_bits);

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

            // Entries (if present)
            if (entries.len > 0) {
                // VarInt count
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
            }

            return data.toOwnedSlice(allocator);
        }

        pub const IndexedEntry = struct {
            index: u32,
            value: EntryType,
        };
    };
}

/// Simple asset with just an ID string
/// Used for: AudioCategories (with volume), TagPatterns, etc.
pub const SimpleStringAsset = struct {
    id: []const u8,
};

/// Serialize a simple string asset (nullBits + VarString id)
pub fn serializeSimpleString(allocator: std.mem.Allocator, entry: *const SimpleStringAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    // nullBits: bit 0 = id present
    try writer.append(allocator, 0x01);
    // id as VarString
    try writeVarString(allocator, writer, entry.id);
}

/// AudioCategory asset (matches Java AudioCategory)
pub const AudioCategoryAsset = struct {
    id: []const u8,
    volume: f32,
};

/// Serialize AudioCategory: nullBits(1) + volume(4) + optional id VarString
pub fn serializeAudioCategory(allocator: std.mem.Allocator, entry: *const AudioCategoryAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    // nullBits: bit 0 = id present
    const has_id: u8 = if (entry.id.len > 0) 0x01 else 0x00;
    try writer.append(allocator, has_id);

    // volume (f32 LE)
    var vol_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &vol_buf, @bitCast(entry.volume), .little);
    try writer.appendSlice(allocator, &vol_buf);

    // id (if present)
    if (entry.id.len > 0) {
        try writeVarString(allocator, writer, entry.id);
    }
}

/// Environment asset (matches Java WorldEnvironment)
pub const EnvironmentAsset = struct {
    id: []const u8,
    water_tint: ?common.Color = null,
    // Simplified: omit fluidParticles and tagIndexes for now
};

/// Serialize Environment (simplified)
/// Format: nullBits(1) + waterTint(3) + idOffset(4) + fluidParticlesOffset(4) + tagIndexesOffset(4) + variable
pub fn serializeEnvironment(allocator: std.mem.Allocator, entry: *const EnvironmentAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    var null_bits: u8 = 0;
    if (entry.id.len > 0) null_bits |= 0x01;
    if (entry.water_tint != null) null_bits |= 0x02;

    try writer.append(allocator, null_bits);

    // waterTint (3 bytes) - always written, zeroed if null
    if (entry.water_tint) |tint| {
        try writer.append(allocator, tint.r);
        try writer.append(allocator, tint.g);
        try writer.append(allocator, tint.b);
    } else {
        try writer.appendNTimes(allocator, 0, 3);
    }

    // Offset table: 3 x i32 = 12 bytes
    const offset_start = writer.items.len;
    try writer.appendNTimes(allocator, 0, 12); // Placeholder for offsets

    // Variable block
    const var_block_start = writer.items.len;

    // id offset
    if (entry.id.len > 0) {
        const id_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[offset_start..][0..4], id_offset, .little);
        try writeVarString(allocator, writer, entry.id);
    } else {
        std.mem.writeInt(i32, writer.items[offset_start..][0..4], -1, .little);
    }

    // fluidParticles offset (not implemented, set to -1)
    std.mem.writeInt(i32, writer.items[offset_start + 4 ..][0..4], -1, .little);

    // tagIndexes offset (not implemented, set to -1)
    std.mem.writeInt(i32, writer.items[offset_start + 8 ..][0..4], -1, .little);
}

/// Build an empty Update* packet with proper format
/// Used as placeholder when we don't have asset data yet
pub fn buildEmptyUpdatePacket(
    allocator: std.mem.Allocator,
    asset_type: common.AssetType,
) ![]u8 {
    // Different packets have different fixed block sizes
    const extra_bytes: []const u8 = switch (asset_type) {
        .environments => &[_]u8{0}, // rebuildMapGeometry (bool)
        else => &[_]u8{},
    };

    return serializeEmptyUpdate(allocator, .init, 0, extra_bytes);
}

test "empty update packet" {
    const allocator = std.testing.allocator;

    const pkt = try serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
    defer allocator.free(pkt);

    try std.testing.expectEqual(@as(usize, 6), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x00), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
}

test "audio category serialization" {
    const allocator = std.testing.allocator;

    const S = AssetSerializer(AudioCategoryAsset);
    const entries = [_]S.IndexedEntry{
        .{ .index = 0, .value = .{ .id = "sfx", .volume = 1.0 } },
        .{ .index = 1, .value = .{ .id = "music", .volume = 0.8 } },
    };

    const pkt = try S.serialize(
        allocator,
        .init,
        2,
        &entries,
        &[_]u8{},
        serializeAudioCategory,
    );
    defer allocator.free(pkt);

    // Check header
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: has entries
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, pkt[2..6], .little)); // maxId

    // Should have 2 entries encoded after the header
    try std.testing.expect(pkt.len > 6);
}
