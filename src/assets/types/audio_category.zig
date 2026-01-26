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

    /// Protocol serialization constants
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 5;
    pub const VARIABLE_FIELD_COUNT: u32 = 1;
    pub const VARIABLE_BLOCK_START: u32 = 5;

    /// Serialize to protocol format
    /// Format: nullBits(1) + volume(4) + if bit 0: VarString id
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.id.len > 0) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // volume (4 bytes f32 LE)
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, @bitCast(self.volume), .little);
        try buf.appendSlice(allocator, &bytes);

        // id string (if present)
        if (self.id.len > 0) {
            // VarInt length
            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(self.id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, self.id);
        }

        return buf.toOwnedSlice(allocator);
    }
};

fn writeVarIntBuf(buf: *[5]u8, value: i32) usize {
    var v: u32 = @bitCast(value);
    var i: usize = 0;
    while (v >= 0x80) {
        buf[i] = @truncate((v & 0x7F) | 0x80);
        v >>= 7;
        i += 1;
    }
    buf[i] = @truncate(v);
    return i + 1;
}

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
