/// AudioCategory Asset Type
///
/// Represents an audio category for controlling volume levels.
/// JSON format: { "Volume": -14.0, "Parent": "AudioCat_NPC" }

const std = @import("std");
const json = @import("../json.zig");
const Allocator = std.mem.Allocator;

/// AudioCategory asset
pub const AudioCategoryAsset = struct {
    /// Asset ID (derived from filename)
    id: []const u8,

    /// Volume in linear scale (converted from dB in JSON)
    volume: f32,

    /// Parent category ID (optional)
    parent: ?[]const u8,

    const Self = @This();

    /// Default values
    pub const DEFAULT_VOLUME_DB: f32 = 0.0;

    /// Parse from JSON content
    pub fn parseJson(allocator: Allocator, id: []const u8, content: []const u8) !Self {
        var parsed = try json.parseJson(allocator, content);
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidJson;
        }

        const obj = parsed.value.object;

        // Get volume in dB, convert to linear
        const volume_db = json.getNumberFieldF32(obj, "Volume") orelse DEFAULT_VOLUME_DB;
        const volume_linear = json.dbToLinear(volume_db);

        // Get optional parent
        const parent = if (json.getStringField(obj, "Parent")) |p|
            try allocator.dupe(u8, p)
        else
            null;

        return .{
            .id = try allocator.dupe(u8, id),
            .volume = volume_linear,
            .parent = parent,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.parent) |p| allocator.free(p);
    }
};

test "AudioCategoryAsset parse basic" {
    const allocator = std.testing.allocator;
    const content =
        \\{
        \\  "Volume": -14.0
        \\}
    ;

    var asset = try AudioCategoryAsset.parseJson(allocator, "test_category", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("test_category", asset.id);
    try std.testing.expectApproxEqRel(@as(f32, 0.2), asset.volume, 0.01);
    try std.testing.expect(asset.parent == null);
}

test "AudioCategoryAsset parse with parent" {
    const allocator = std.testing.allocator;
    const content =
        \\{
        \\  "Volume": 0,
        \\  "Parent": "AudioCat_NPC"
        \\}
    ;

    var asset = try AudioCategoryAsset.parseJson(allocator, "test_npc", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("test_npc", asset.id);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), asset.volume, 0.001);
    try std.testing.expectEqualStrings("AudioCat_NPC", asset.parent.?);
}
