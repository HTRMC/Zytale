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
};

test "EqualizerEffectAsset defaults" {
    const allocator = std.testing.allocator;
    const content = "{}";

    var asset = try EqualizerEffectAsset.parseJson(allocator, "test_eq", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("test_eq", asset.id);
    try std.testing.expectApproxEqRel(EqualizerEffectAsset.DEFAULTS.low_cut_off, asset.low_cut_off, 0.001);
}
