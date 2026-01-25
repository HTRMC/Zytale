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

// Asset type imports
const audio_category = @import("types/audio_category.zig");
const reverb_effect = @import("types/reverb_effect.zig");
const equalizer_effect = @import("types/equalizer_effect.zig");
const tag_pattern = @import("types/tag_pattern.zig");
const trail = @import("types/trail.zig");

const UpdateType = common.UpdateType;
pub const AudioCategoryAssetType = audio_category.AudioCategoryAsset;
pub const ReverbEffectAssetType = reverb_effect.ReverbEffectAsset;
pub const EqualizerEffectAssetType = equalizer_effect.EqualizerEffectAsset;
pub const TagPatternAssetType = tag_pattern.TagPatternAsset;
pub const TagPatternType = tag_pattern.TagPatternType;
pub const TrailAssetType = trail.TrailAsset;
pub const FXRenderMode = trail.FXRenderMode;
pub const EdgeData = trail.EdgeData;

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

/// Serialize an empty Update* packet (no assets, but with empty dictionary)
/// The client expects a dictionary to always be present, even if empty
pub fn serializeEmptyUpdate(
    allocator: std.mem.Allocator,
    update_type: UpdateType,
    max_id: i32,
    extra_fixed_bytes: []const u8,
) ![]u8 {
    // Size: nullBits(1) + type(1) + maxId(4) + extra + VarInt(0) for empty dict
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

        pub const IndexedEntry = struct {
            index: u32,
            value: EntryType,
        };
    };
}

/// String-keyed asset serializer (no maxId, string keys)
/// Used by: UpdateTrails
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

/// Serialize empty string-keyed Update packet (3 bytes)
/// Includes empty dictionary (VarInt 0) instead of null dictionary
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

/// Serialize ReverbEffect
/// Format from Java: nullBits(1) + 13 f32s(52) + bool(1) + [id VarString if nullBits & 1]
/// FIXED_BLOCK_SIZE = 54, NO offset - id is inline
pub fn serializeReverbEffect(allocator: std.mem.Allocator, entry: *const ReverbEffectAssetType, writer: *std.ArrayListUnmanaged(u8)) !void {
    // nullBits: bit 0 = id present
    const has_id: u8 = if (entry.id.len > 0) 0x01 else 0x00;
    try writer.append(allocator, has_id);

    // 13 f32 values (52 bytes) in exact order from Java
    try writeF32(allocator, writer, entry.dry_gain);
    try writeF32(allocator, writer, entry.modal_density);
    try writeF32(allocator, writer, entry.diffusion);
    try writeF32(allocator, writer, entry.gain);
    try writeF32(allocator, writer, entry.high_frequency_gain);
    try writeF32(allocator, writer, entry.decay_time);
    try writeF32(allocator, writer, entry.high_frequency_decay_ratio);
    try writeF32(allocator, writer, entry.reflection_gain);
    try writeF32(allocator, writer, entry.reflection_delay);
    try writeF32(allocator, writer, entry.late_reverb_gain);
    try writeF32(allocator, writer, entry.late_reverb_delay);
    try writeF32(allocator, writer, entry.room_rolloff_factor);
    try writeF32(allocator, writer, entry.air_absorption_hf_gain);

    // bool (1 byte)
    try writer.append(allocator, if (entry.limit_decay_high_frequency) @as(u8, 1) else @as(u8, 0));

    // id VarString (inline, no offset!) - only if present
    if (entry.id.len > 0) {
        try writeVarString(allocator, writer, entry.id);
    }
}

/// Serialize EqualizerEffect
/// Format from Java: nullBits(1) + 10 f32s(40) + [id VarString if nullBits & 1]
/// FIXED_BLOCK_SIZE = 41, NO offset - id is inline
pub fn serializeEqualizerEffect(allocator: std.mem.Allocator, entry: *const EqualizerEffectAssetType, writer: *std.ArrayListUnmanaged(u8)) !void {
    // nullBits: bit 0 = id present
    const has_id: u8 = if (entry.id.len > 0) 0x01 else 0x00;
    try writer.append(allocator, has_id);

    // 10 f32 values (40 bytes) in exact order from Java
    try writeF32(allocator, writer, entry.low_gain);
    try writeF32(allocator, writer, entry.low_cut_off);
    try writeF32(allocator, writer, entry.low_mid_gain);
    try writeF32(allocator, writer, entry.low_mid_center);
    try writeF32(allocator, writer, entry.low_mid_width);
    try writeF32(allocator, writer, entry.high_mid_gain);
    try writeF32(allocator, writer, entry.high_mid_center);
    try writeF32(allocator, writer, entry.high_mid_width);
    try writeF32(allocator, writer, entry.high_gain);
    try writeF32(allocator, writer, entry.high_cut_off);

    // id VarString (inline, no offset!) - only if present
    if (entry.id.len > 0) {
        try writeVarString(allocator, writer, entry.id);
    }
}

/// Serialize TagPattern
/// Format from Java: nullBits(1) + type(1) + tagIndex(4) + operandsOffset(4) + notOffset(4) + [variable]
/// FIXED_BLOCK_SIZE = 6, VARIABLE_BLOCK_START = 14
/// NOTE: TagPattern has NO id field in the protocol!
pub fn serializeTagPattern(allocator: std.mem.Allocator, entry: *const TagPatternAssetType, writer: *std.ArrayListUnmanaged(u8)) !void {
    try serializeTagPatternRecursive(allocator, entry, writer);
}

fn serializeTagPatternRecursive(allocator: std.mem.Allocator, entry: *const TagPatternAssetType, writer: *std.ArrayListUnmanaged(u8)) !void {
    const entry_start = writer.items.len;

    // nullBits: bit 0 = operands present, bit 1 = not present
    var null_bits: u8 = 0;
    if (entry.operands != null) null_bits |= 0x01;
    if (entry.not_pattern != null) null_bits |= 0x02;
    try writer.append(allocator, null_bits);

    // type (1 byte)
    try writer.append(allocator, @intFromEnum(entry.type));

    // tagIndex (4 bytes)
    try writeI32(allocator, writer, entry.tag_index);

    // operandsOffset placeholder (4 bytes) - offset 6
    const operands_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // notOffset placeholder (4 bytes) - offset 10
    const not_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // Variable block starts at offset 14 from entry_start
    const var_block_start = entry_start + 14;

    // operands (if present)
    if (entry.operands) |operands| {
        // Write offset relative to var_block_start
        const operands_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[operands_offset_pos..][0..4], operands_offset, .little);

        // Write VarInt count
        var count_buf: [5]u8 = undefined;
        const count_len = writeVarInt(&count_buf, @intCast(operands.len));
        try writer.appendSlice(allocator, count_buf[0..count_len]);

        // Write each operand recursively
        for (operands) |*op| {
            try serializeTagPatternRecursive(allocator, op, writer);
        }
    } else {
        std.mem.writeInt(i32, writer.items[operands_offset_pos..][0..4], -1, .little);
    }

    // not (if present)
    if (entry.not_pattern) |np| {
        // Write offset relative to var_block_start
        const not_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[not_offset_pos..][0..4], not_offset, .little);

        // Write the not pattern recursively
        try serializeTagPatternRecursive(allocator, np, writer);
    } else {
        std.mem.writeInt(i32, writer.items[not_offset_pos..][0..4], -1, .little);
    }
}

/// Serialize Trail
/// Format from Java:
/// nullBits(1) + lifeSpan(4) + roll(4) + start Edge(9) + end Edge(9) + lightInfluence(4) +
/// renderMode(1) + intersectionHighlight(8) + smooth(1) + frameSize(8) + frameRange(8) +
/// frameLifeSpan(4) + idOffset(4) + textureOffset(4) + [variable]
/// FIXED_BLOCK_SIZE = 61, VARIABLE_BLOCK_START = 69
///
/// Java nullBits mapping (correct):
/// - bit 0 (0x01) = start (Edge) present
/// - bit 1 (0x02) = end (Edge) present
/// - bit 2 (0x04) = intersectionHighlight present
/// - bit 3 (0x08) = frameSize present
/// - bit 4 (0x10) = frameRange present
/// - bit 5 (0x20) = id present
/// - bit 6 (0x40) = texture present
pub fn serializeTrail(allocator: std.mem.Allocator, entry: *const TrailAssetType, writer: *std.ArrayListUnmanaged(u8)) !void {
    const entry_start = writer.items.len;

    // nullBits - MUST match Java bit mapping!
    var null_bits: u8 = 0;
    if (entry.start != null) null_bits |= 0x01; // bit 0
    if (entry.end != null) null_bits |= 0x02; // bit 1
    // bit 2 = intersectionHighlight (not implemented)
    // bit 3 = frameSize (not implemented)
    // bit 4 = frameRange (not implemented)
    if (entry.id.len > 0) null_bits |= 0x20; // bit 5
    if (entry.texture.len > 0) null_bits |= 0x40; // bit 6
    try writer.append(allocator, null_bits);

    // lifeSpan (i32)
    try writeI32(allocator, writer, entry.life_span);

    // roll (f32)
    try writeF32(allocator, writer, entry.roll);

    // start Edge (9 bytes) - nullBits(1) + color(4) + width(4)
    if (entry.start) |start| {
        // Edge nullBits: bit 0 = color present
        try writer.append(allocator, 0x01); // color always present
        // ColorAlpha (4 bytes RGBA)
        try writer.append(allocator, start.color.r);
        try writer.append(allocator, start.color.g);
        try writer.append(allocator, start.color.b);
        try writer.append(allocator, start.color.a);
        // width (f32)
        try writeF32(allocator, writer, start.size);
    } else {
        try writer.appendNTimes(allocator, 0, 9);
    }

    // end Edge (9 bytes)
    if (entry.end) |end| {
        try writer.append(allocator, 0x01);
        try writer.append(allocator, end.color.r);
        try writer.append(allocator, end.color.g);
        try writer.append(allocator, end.color.b);
        try writer.append(allocator, end.color.a);
        try writeF32(allocator, writer, end.size);
    } else {
        try writer.appendNTimes(allocator, 0, 9);
    }

    // lightInfluence (f32)
    try writeF32(allocator, writer, entry.light_influence);

    // renderMode (u8)
    try writer.append(allocator, @intFromEnum(entry.render_mode));

    // intersectionHighlight (8 bytes) - not implemented, write zeros
    try writer.appendNTimes(allocator, 0, 8);

    // smooth (bool)
    try writer.append(allocator, if (entry.smooth) @as(u8, 1) else @as(u8, 0));

    // frameSize Vector2i (8 bytes) - not implemented, write zeros
    try writer.appendNTimes(allocator, 0, 8);

    // frameRange Range (8 bytes) - not implemented, write zeros
    try writer.appendNTimes(allocator, 0, 8);

    // frameLifeSpan (i32)
    try writeI32(allocator, writer, entry.frame_life_span);

    // idOffset placeholder (4 bytes) - offset 61
    const id_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // textureOffset placeholder (4 bytes) - offset 65
    const texture_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4);

    // Variable block starts at offset 69 from entry_start
    const var_block_start = entry_start + 69;

    // id VarString (if present)
    if (entry.id.len > 0) {
        const id_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[id_offset_pos..][0..4], id_offset, .little);
        try writeVarString(allocator, writer, entry.id);
    } else {
        std.mem.writeInt(i32, writer.items[id_offset_pos..][0..4], -1, .little);
    }

    // texture VarString (if present)
    if (entry.texture.len > 0) {
        const texture_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[texture_offset_pos..][0..4], texture_offset, .little);
        try writeVarString(allocator, writer, entry.texture);
    } else {
        std.mem.writeInt(i32, writer.items[texture_offset_pos..][0..4], -1, .little);
    }
}

/// Helper to write f32 as little-endian bytes
fn writeF32(allocator: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), value: f32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, @bitCast(value), .little);
    try writer.appendSlice(allocator, &buf);
}

/// Helper to write i32 as little-endian bytes
fn writeI32(allocator: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), value: i32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, value, .little);
    try writer.appendSlice(allocator, &buf);
}

/// Build an empty Update* packet with proper format for each asset type
/// Different asset types have different header structures based on FIXED_BLOCK_SIZE
/// Used as placeholder when we don't have asset data yet
pub fn buildEmptyUpdatePacket(
    allocator: std.mem.Allocator,
    asset_type: common.AssetType,
) ![]u8 {
    return switch (asset_type) {
        // String-keyed: 3 bytes (nullBits + type + VarInt 0)
        .trails => serializeEmptyStringKeyedUpdate(allocator, .init),

        // FIXED=10: nullBits + type + maxId + 4 booleans + VarInt 0
        .block_types => serializeEmptyUpdate(allocator, .init, 0, &[_]u8{ 0, 0, 0, 0 }),

        // FIXED=7: nullBits + type + maxId + 1 boolean + VarInt 0
        .environments => serializeEmptyUpdate(allocator, .init, 0, &[_]u8{0}),

        // FIXED=6: nullBits + type + maxId + VarInt 0 (integer-keyed with maxId)
        .block_hitboxes,
        .block_sound_sets,
        .item_sound_sets,
        .weathers,
        => serializeEmptyUpdate(allocator, .init, 0, &[_]u8{}),

        // FIXED=4: nullBits + type + 2 booleans + offset table + VarInt counts
        .items => blk: {
            // Items has 2 booleans + offset table for 2 variable fields
            const buf = try allocator.alloc(u8, 14);
            buf[0] = 0x03; // nullBits: both fields present (items and removedItems)
            buf[1] = 0x00; // type = Init
            buf[2] = 0; // updateModels = false
            buf[3] = 0; // updateIcons = false
            // Offset to items (at variable block start = offset 0)
            std.mem.writeInt(i32, buf[4..8], 0, .little);
            // Offset to removedItems (after items VarInt 0 = offset 1)
            std.mem.writeInt(i32, buf[8..12], 1, .little);
            buf[12] = 0x00; // items count = 0
            buf[13] = 0x00; // removedItems count = 0
            break :blk buf;
        },

        // FIXED=4: nullBits + type + 2 booleans + offset table + VarInt counts
        .item_player_animations => blk: {
            const buf = try allocator.alloc(u8, 14);
            buf[0] = 0x03; // nullBits: both fields present
            buf[1] = 0x00; // type = Init
            buf[2] = 0; // bool1
            buf[3] = 0; // bool2
            std.mem.writeInt(i32, buf[4..8], 0, .little);
            std.mem.writeInt(i32, buf[8..12], 1, .little);
            buf[12] = 0x00;
            buf[13] = 0x00;
            break :blk buf;
        },

        // FIXED=2 with 2 variable fields (need offset table)
        .particle_systems, .particle_spawners, .recipes => blk: {
            const buf = try allocator.alloc(u8, 12); // 1+1+8+2
            buf[0] = 0x03; // nullBits: both fields present
            buf[1] = 0x00; // type = Init
            std.mem.writeInt(i32, buf[2..6], 0, .little); // offset to field 0
            std.mem.writeInt(i32, buf[6..10], 1, .little); // offset to field 1
            buf[10] = 0x00; // field 0 count = 0
            buf[11] = 0x00; // field 1 count = 0
            break :blk buf;
        },

        // FIXED=2: Most packets - just nullBits + type + VarInt 0 (NO maxId!)
        else => blk: {
            const buf = try allocator.alloc(u8, 3);
            buf[0] = 0x01; // nullBits: dictionary present
            buf[1] = 0x00; // type = Init
            buf[2] = 0x00; // VarInt count = 0
            break :blk buf;
        },
    };
}

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

test "buildEmptyUpdatePacket - FIXED=2 packets have no maxId" {
    const allocator = std.testing.allocator;

    // Most packets have FIXED_BLOCK_SIZE=2, meaning no maxId field
    const pkt = try buildEmptyUpdatePacket(allocator, .audio_categories);
    defer allocator.free(pkt);

    // Should be 3 bytes: nullBits(1) + type(1) + VarInt 0(1)
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: dictionary present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[2]); // VarInt count = 0
}

test "buildEmptyUpdatePacket - block_types has maxId + 4 booleans" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyUpdatePacket(allocator, .block_types);
    defer allocator.free(pkt);

    // FIXED=10: nullBits(1) + type(1) + maxId(4) + 4 booleans(4) + VarInt 0(1) = 11 bytes
    try std.testing.expectEqual(@as(usize, 11), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type = Init
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId = 0
    try std.testing.expectEqual(@as(u8, 0), pkt[6]); // bool 1
    try std.testing.expectEqual(@as(u8, 0), pkt[7]); // bool 2
    try std.testing.expectEqual(@as(u8, 0), pkt[8]); // bool 3
    try std.testing.expectEqual(@as(u8, 0), pkt[9]); // bool 4
    try std.testing.expectEqual(@as(u8, 0x00), pkt[10]); // VarInt count = 0
}

test "buildEmptyUpdatePacket - environments has maxId + 1 boolean" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyUpdatePacket(allocator, .environments);
    defer allocator.free(pkt);

    // FIXED=7: nullBits(1) + type(1) + maxId(4) + 1 boolean(1) + VarInt 0(1) = 8 bytes
    try std.testing.expectEqual(@as(usize, 8), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0), pkt[6]); // rebuildMapGeometry = false
    try std.testing.expectEqual(@as(u8, 0x00), pkt[7]); // VarInt count = 0
}

test "buildEmptyUpdatePacket - block_sound_sets has maxId (FIXED=6)" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyUpdatePacket(allocator, .block_sound_sets);
    defer allocator.free(pkt);

    // FIXED=6: nullBits(1) + type(1) + maxId(4) + VarInt 0(1) = 7 bytes
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0x00), pkt[6]); // VarInt count = 0
}

test "buildEmptyUpdatePacket - item_sound_sets has maxId (FIXED=6)" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyUpdatePacket(allocator, .item_sound_sets);
    defer allocator.free(pkt);

    // FIXED=6: nullBits(1) + type(1) + maxId(4) + VarInt 0(1) = 7 bytes
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0x00), pkt[6]); // VarInt count = 0
}

test "buildEmptyUpdatePacket - weathers has maxId (FIXED=6)" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyUpdatePacket(allocator, .weathers);
    defer allocator.free(pkt);

    // FIXED=6: nullBits(1) + type(1) + maxId(4) + VarInt 0(1) = 7 bytes
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0x00), pkt[6]); // VarInt count = 0
}

test "buildEmptyUpdatePacket - trails is string-keyed (no maxId)" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyUpdatePacket(allocator, .trails);
    defer allocator.free(pkt);

    // String-keyed: nullBits(1) + type(1) + VarInt 0(1) = 3 bytes
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(u8, 0x00), pkt[2]); // VarInt count = 0
}

test "buildEmptyUpdatePacket - items has offset table" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyUpdatePacket(allocator, .items);
    defer allocator.free(pkt);

    // FIXED=4: nullBits(1) + type(1) + 2 bools(2) + 2 offsets(8) + 2 VarInts(2) = 14 bytes
    try std.testing.expectEqual(@as(usize, 14), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x03), pkt[0]); // nullBits: both fields present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type = Init
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

test "AssetSerializer with zero entries produces valid empty dictionary" {
    const allocator = std.testing.allocator;

    const S = AssetSerializer(AudioCategoryAsset);
    const entries = [_]S.IndexedEntry{};

    const pkt = try S.serialize(
        allocator,
        .init,
        0,
        &entries,
        &[_]u8{},
        serializeAudioCategory,
    );
    defer allocator.free(pkt);

    // Must be 7 bytes: nullBits(1) + type(1) + maxId(4) + VarInt count 0(1)
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: dictionary IS present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0x00), pkt[6]); // VarInt count = 0 (empty dictionary)
}

test "StringKeyedSerializer with zero entries produces valid empty dictionary" {
    const allocator = std.testing.allocator;

    const S = StringKeyedSerializer(TrailAssetType);
    const entries = [_]S.StringKeyedEntry{};

    const pkt = try S.serialize(
        allocator,
        .init,
        &entries,
        serializeTrail,
    );
    defer allocator.free(pkt);

    // Must be 3 bytes: nullBits(1) + type(1) + VarInt count 0(1)
    try std.testing.expectEqual(@as(usize, 3), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: dictionary IS present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // UpdateType.init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[2]); // VarInt count = 0 (empty dictionary)
}
