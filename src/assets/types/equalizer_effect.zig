/// EqualizerEffect Asset Type
///
/// Represents an equalizer effect with gain/frequency controls for different bands.

const std = @import("std");
const json = @import("../json.zig");
const Allocator = std.mem.Allocator;

/// EqualizerEffect asset
pub const EqualizerEffectAsset = struct {
    /// Asset ID (derived from filename)
    id: []const u8,

    /// Low band gain (linear)
    low_gain: f32,

    /// Low band cutoff frequency (Hz)
    low_cut_off: f32,

    /// Low-mid band gain (linear)
    low_mid_gain: f32,

    /// Low-mid band center frequency (Hz)
    low_mid_center: f32,

    /// Low-mid band width
    low_mid_width: f32,

    /// High-mid band gain (linear)
    high_mid_gain: f32,

    /// High-mid band center frequency (Hz)
    high_mid_center: f32,

    /// High-mid band width
    high_mid_width: f32,

    /// High band gain (linear)
    high_gain: f32,

    /// High band cutoff frequency (Hz)
    high_cut_off: f32,

    const Self = @This();

    /// Default values (flat EQ)
    pub const DEFAULTS = Self{
        .id = "",
        .low_gain = 1.0,
        .low_cut_off = 200.0,
        .low_mid_gain = 1.0,
        .low_mid_center = 500.0,
        .low_mid_width = 1.0,
        .high_mid_gain = 1.0,
        .high_mid_center = 3000.0,
        .high_mid_width = 1.0,
        .high_gain = 1.0,
        .high_cut_off = 6000.0,
    };

    /// Parse from JSON content
    pub fn parseJson(allocator: Allocator, id: []const u8, content: []const u8) !Self {
        var parsed = try json.parseJson(allocator, content);
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidJson;
        }

        const obj = parsed.value.object;

        // Helper to get dB value and convert to linear
        const getGain = struct {
            fn f(o: std.json.ObjectMap, field: []const u8, default_linear: f32) f32 {
                if (json.getNumberFieldF32(o, field)) |db| {
                    return json.dbToLinear(db);
                }
                return default_linear;
            }
        }.f;

        // Helper to get raw float value
        const getFloat = struct {
            fn f(o: std.json.ObjectMap, field: []const u8, default: f32) f32 {
                return json.getNumberFieldF32(o, field) orelse default;
            }
        }.f;

        return .{
            .id = try allocator.dupe(u8, id),
            .low_gain = getGain(obj, "LowGain", DEFAULTS.low_gain),
            .low_cut_off = getFloat(obj, "LowCutOff", DEFAULTS.low_cut_off),
            .low_mid_gain = getGain(obj, "LowMidGain", DEFAULTS.low_mid_gain),
            .low_mid_center = getFloat(obj, "LowMidCenter", DEFAULTS.low_mid_center),
            .low_mid_width = getFloat(obj, "LowMidWidth", DEFAULTS.low_mid_width),
            .high_mid_gain = getGain(obj, "HighMidGain", DEFAULTS.high_mid_gain),
            .high_mid_center = getFloat(obj, "HighMidCenter", DEFAULTS.high_mid_center),
            .high_mid_width = getFloat(obj, "HighMidWidth", DEFAULTS.high_mid_width),
            .high_gain = getGain(obj, "HighGain", DEFAULTS.high_gain),
            .high_cut_off = getFloat(obj, "HighCutOff", DEFAULTS.high_cut_off),
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.id);
    }

    /// Protocol serialization constants
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 41;
    pub const VARIABLE_FIELD_COUNT: u32 = 1;
    pub const VARIABLE_BLOCK_START: u32 = 41;

    /// Serialize to protocol format
    /// Format: nullBits(1) + 10 floats(40) + if bit 0: VarString id
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.id.len > 0) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // 10 float parameters (40 bytes)
        try writeF32(&buf, allocator, self.low_gain);
        try writeF32(&buf, allocator, self.low_cut_off);
        try writeF32(&buf, allocator, self.low_mid_gain);
        try writeF32(&buf, allocator, self.low_mid_center);
        try writeF32(&buf, allocator, self.low_mid_width);
        try writeF32(&buf, allocator, self.high_mid_gain);
        try writeF32(&buf, allocator, self.high_mid_center);
        try writeF32(&buf, allocator, self.high_mid_width);
        try writeF32(&buf, allocator, self.high_gain);
        try writeF32(&buf, allocator, self.high_cut_off);

        // id string (if present)
        if (self.id.len > 0) {
            try writeVarString(&buf, allocator, self.id);
        }

        return buf.toOwnedSlice(allocator);
    }
};

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    var vi_buf: [5]u8 = undefined;
    const vi_len = writeVarIntBuf(&vi_buf, @intCast(str.len));
    try buf.appendSlice(allocator, vi_buf[0..vi_len]);
    try buf.appendSlice(allocator, str);
}

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

test "EqualizerEffectAsset defaults" {
    const allocator = std.testing.allocator;
    const content = "{}";

    var asset = try EqualizerEffectAsset.parseJson(allocator, "test_eq", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("test_eq", asset.id);
    try std.testing.expectApproxEqRel(EqualizerEffectAsset.DEFAULTS.low_cut_off, asset.low_cut_off, 0.001);
}
