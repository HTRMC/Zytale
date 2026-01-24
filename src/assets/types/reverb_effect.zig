/// ReverbEffect Asset Type
///
/// Represents a reverb effect with various audio parameters.
/// All gain values are stored in linear form (converted from dB in JSON).

const std = @import("std");
const json = @import("../json.zig");
const Allocator = std.mem.Allocator;

/// ReverbEffect asset
pub const ReverbEffectAsset = struct {
    /// Asset ID (derived from filename)
    id: []const u8,

    /// Dry signal gain (linear)
    dry_gain: f32,

    /// Modal density (0.0 - 1.0)
    modal_density: f32,

    /// Diffusion (0.0 - 1.0)
    diffusion: f32,

    /// Overall gain (linear)
    gain: f32,

    /// High frequency gain (linear)
    high_frequency_gain: f32,

    /// Decay time in seconds
    decay_time: f32,

    /// High frequency decay ratio (0.1 - 2.0)
    high_frequency_decay_ratio: f32,

    /// Reflections gain (linear)
    reflection_gain: f32,

    /// Reflections delay in seconds
    reflection_delay: f32,

    /// Late reverb gain (linear)
    late_reverb_gain: f32,

    /// Late reverb delay in seconds
    late_reverb_delay: f32,

    /// Room rolloff factor
    room_rolloff_factor: f32,

    /// Air absorption HF gain (linear)
    air_absorption_hf_gain: f32,

    /// Limit decay at high frequencies
    limit_decay_high_frequency: bool,

    const Self = @This();

    /// Default values (EAX preset: Generic)
    pub const DEFAULTS = Self{
        .id = "",
        .dry_gain = 1.0,
        .modal_density = 1.0,
        .diffusion = 1.0,
        .gain = 0.316, // -10 dB
        .high_frequency_gain = 0.891, // -1 dB
        .decay_time = 1.49,
        .high_frequency_decay_ratio = 0.83,
        .reflection_gain = 0.05, // -26 dB
        .reflection_delay = 0.007,
        .late_reverb_gain = 1.26, // +2 dB
        .late_reverb_delay = 0.011,
        .room_rolloff_factor = 0.0,
        .air_absorption_hf_gain = 0.994, // -0.05 dB
        .limit_decay_high_frequency = true,
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
            .dry_gain = getGain(obj, "DryGain", DEFAULTS.dry_gain),
            .modal_density = getFloat(obj, "ModalDensity", DEFAULTS.modal_density),
            .diffusion = getFloat(obj, "Diffusion", DEFAULTS.diffusion),
            .gain = getGain(obj, "Gain", DEFAULTS.gain),
            .high_frequency_gain = getGain(obj, "HighFrequencyGain", DEFAULTS.high_frequency_gain),
            .decay_time = getFloat(obj, "DecayTime", DEFAULTS.decay_time),
            .high_frequency_decay_ratio = getFloat(obj, "HighFrequencyDecayRatio", DEFAULTS.high_frequency_decay_ratio),
            .reflection_gain = getGain(obj, "ReflectionGain", DEFAULTS.reflection_gain),
            .reflection_delay = getFloat(obj, "ReflectionDelay", DEFAULTS.reflection_delay),
            .late_reverb_gain = getGain(obj, "LateReverbGain", DEFAULTS.late_reverb_gain),
            .late_reverb_delay = getFloat(obj, "LateReverbDelay", DEFAULTS.late_reverb_delay),
            .room_rolloff_factor = getFloat(obj, "RoomRolloffFactor", DEFAULTS.room_rolloff_factor),
            // JSON uses typo "AirAbsorbptionHighFrequencyGain" - try both variants
            .air_absorption_hf_gain = blk: {
                if (json.getNumberFieldF32(obj, "AirAbsorbptionHighFrequencyGain")) |db| {
                    break :blk json.dbToLinear(db);
                }
                if (json.getNumberFieldF32(obj, "AirAbsorptionHFGain")) |db| {
                    break :blk json.dbToLinear(db);
                }
                break :blk DEFAULTS.air_absorption_hf_gain;
            },
            .limit_decay_high_frequency = json.getBoolField(obj, "LimitDecayHighFrequency") orelse DEFAULTS.limit_decay_high_frequency,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.id);
    }
};

test "ReverbEffectAsset defaults" {
    const allocator = std.testing.allocator;
    const content = "{}";

    var asset = try ReverbEffectAsset.parseJson(allocator, "test_reverb", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("test_reverb", asset.id);
    try std.testing.expectApproxEqRel(ReverbEffectAsset.DEFAULTS.decay_time, asset.decay_time, 0.001);
}
