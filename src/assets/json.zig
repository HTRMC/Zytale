/// JSON Parsing Utilities for Asset Files
///
/// Provides helpers for parsing JSON asset files from the ZIP archive.

const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.asset_json);

/// Convert decibels to linear gain
/// Formula: linear = 10^(dB/20)
pub fn dbToLinear(db: f32) f32 {
    return std.math.pow(f32, 10.0, db / 20.0);
}

/// Convert linear gain to decibels
/// Formula: dB = 20 * log10(linear)
pub fn linearToDb(linear: f32) f32 {
    if (linear <= 0) return -std.math.inf(f32);
    return 20.0 * std.math.log10(linear);
}

/// Extract asset ID from a file path
/// Example: "Server/Audio/AudioCategories/NPC/AudioCat_NPC_Antelope.json" -> "AudioCat_NPC_Antelope"
pub fn extractAssetId(allocator: Allocator, path: []const u8) ![]const u8 {
    // Find the last slash
    const filename_start = if (std.mem.lastIndexOf(u8, path, "/")) |idx|
        idx + 1
    else
        0;

    // Remove .json extension
    const filename = path[filename_start..];
    const name_end = if (std.mem.endsWith(u8, filename, ".json"))
        filename.len - 5
    else
        filename.len;

    return try allocator.dupe(u8, filename[0..name_end]);
}

/// Parse a JSON object and get a string field
pub fn getStringField(obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    if (obj.get(field)) |val| {
        return switch (val) {
            .string => |s| s,
            else => null,
        };
    }
    return null;
}

/// Parse a JSON object and get a number field as f32
pub fn getNumberFieldF32(obj: std.json.ObjectMap, field: []const u8) ?f32 {
    if (obj.get(field)) |val| {
        return switch (val) {
            .float => |f| @floatCast(f),
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }
    return null;
}

/// Parse a JSON object and get a number field as i32
pub fn getNumberFieldI32(obj: std.json.ObjectMap, field: []const u8) ?i32 {
    if (obj.get(field)) |val| {
        return switch (val) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            else => null,
        };
    }
    return null;
}

/// Parse a JSON object and get a boolean field
pub fn getBoolField(obj: std.json.ObjectMap, field: []const u8) ?bool {
    if (obj.get(field)) |val| {
        return switch (val) {
            .bool => |b| b,
            else => null,
        };
    }
    return null;
}

/// Parse a JSON object and get an array field
pub fn getArrayField(obj: std.json.ObjectMap, field: []const u8) ?std.json.Array {
    if (obj.get(field)) |val| {
        return switch (val) {
            .array => |a| a,
            else => null,
        };
    }
    return null;
}

/// Parse a JSON object and get an object field
pub fn getObjectField(obj: std.json.ObjectMap, field: []const u8) ?std.json.ObjectMap {
    if (obj.get(field)) |val| {
        return switch (val) {
            .object => |o| o,
            else => null,
        };
    }
    return null;
}

/// Parse JSON content into a std.json.Value
pub fn parseJson(allocator: Allocator, content: []const u8) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, allocator, content, .{
        .allocate = .alloc_always,
    });
}

test "dbToLinear conversions" {
    // 0 dB = 1.0 linear
    try std.testing.expectApproxEqRel(@as(f32, 1.0), dbToLinear(0), 0.001);

    // -6 dB ~= 0.5 linear
    try std.testing.expectApproxEqRel(@as(f32, 0.501), dbToLinear(-6), 0.01);

    // -20 dB = 0.1 linear
    try std.testing.expectApproxEqRel(@as(f32, 0.1), dbToLinear(-20), 0.001);

    // 20 dB = 10 linear
    try std.testing.expectApproxEqRel(@as(f32, 10.0), dbToLinear(20), 0.001);
}

test "extractAssetId" {
    const allocator = std.testing.allocator;

    const id1 = try extractAssetId(allocator, "Server/Audio/AudioCategories/AudioCat_Music.json");
    defer allocator.free(id1);
    try std.testing.expectEqualStrings("AudioCat_Music", id1);

    const id2 = try extractAssetId(allocator, "Server/TagPatterns/Bush_Or_Seed.json");
    defer allocator.free(id2);
    try std.testing.expectEqualStrings("Bush_Or_Seed", id2);
}
