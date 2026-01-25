/// EntityEffect Asset Type
///
/// Represents an entity effect (buff/debuff) with duration, stat modifiers, etc.
/// Matches the Java protocol EntityEffect serialization format.

const std = @import("std");
const json = @import("../json.zig");
const Allocator = std.mem.Allocator;

/// Protocol OverlapBehavior enum (matches Java protocol)
/// Values from com.hypixel.hytale.protocol.OverlapBehavior
pub const OverlapBehavior = enum(u8) {
    extend = 0,
    overwrite = 1,
    ignore = 2,

    pub fn fromString(s: []const u8) OverlapBehavior {
        if (std.ascii.eqlIgnoreCase(s, "Extend") or std.ascii.eqlIgnoreCase(s, "EXTEND")) {
            return .extend;
        } else if (std.ascii.eqlIgnoreCase(s, "Overwrite") or std.ascii.eqlIgnoreCase(s, "OVERWRITE")) {
            return .overwrite;
        } else if (std.ascii.eqlIgnoreCase(s, "Ignore") or std.ascii.eqlIgnoreCase(s, "IGNORE")) {
            return .ignore;
        }
        return .ignore; // Default from Java config
    }
};

/// Protocol ValueType enum (matches Java protocol)
/// Values from com.hypixel.hytale.protocol.ValueType
pub const ValueType = enum(u8) {
    percent = 0,
    absolute = 1,

    pub fn fromString(s: []const u8) ValueType {
        if (std.ascii.eqlIgnoreCase(s, "Percent") or std.ascii.eqlIgnoreCase(s, "PERCENT")) {
            return .percent;
        } else if (std.ascii.eqlIgnoreCase(s, "Absolute") or std.ascii.eqlIgnoreCase(s, "ABSOLUTE")) {
            return .absolute;
        }
        return .absolute; // Default from Java config
    }
};

/// Stat modifier entry (key = stat type index, value = modifier value)
pub const StatModifier = struct {
    key: i32,
    value: f32,
};

/// EntityEffect asset
pub const EntityEffectAsset = struct {
    /// Asset ID (derived from filename)
    id: []const u8,

    /// Display name (localization key)
    name: ?[]const u8,

    /// World removal sound event index (resolved from ID)
    world_removal_sound_index: i32,

    /// Local removal sound event index (resolved from ID)
    local_removal_sound_index: i32,

    /// Duration in seconds
    duration: f32,

    /// Whether effect has infinite duration
    infinite: bool,

    /// Whether this is a debuff
    debuff: bool,

    /// Behavior when effect overlaps with existing
    overlap_behavior: OverlapBehavior,

    /// Cooldown for damage calculator
    damage_calculator_cooldown: f64,

    /// Value type for stat modifiers
    value_type: ValueType,

    /// Status effect icon path
    status_effect_icon: ?[]const u8,

    /// Stat modifiers (key = stat type index, value = modifier)
    /// Stored as a dynamic array since we can't have hashmaps in this struct easily
    stat_modifiers: ?[]StatModifier,

    // NOTE: applicationEffects and modelOverride are complex nested types
    // that we skip for now - client accepts them as null

    const Self = @This();

    /// Default values matching Java EntityEffect defaults
    pub const DEFAULTS = Self{
        .id = "",
        .name = null,
        .world_removal_sound_index = 0,
        .local_removal_sound_index = 0,
        .duration = 0,
        .infinite = false,
        .debuff = false,
        .overlap_behavior = .ignore, // Java config default: OverlapBehavior.IGNORE
        .damage_calculator_cooldown = 0,
        .value_type = .absolute, // Java config default: ValueType.Absolute
        .status_effect_icon = null,
        .stat_modifiers = null,
    };

    /// Parse from JSON content
    pub fn parseJson(allocator: Allocator, id: []const u8, content: []const u8) !Self {
        var parsed = try json.parseJson(allocator, content);
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidJson;
        }

        const obj = parsed.value.object;

        // Parse name
        const name: ?[]const u8 = if (json.getStringField(obj, "Name")) |n|
            try allocator.dupe(u8, n)
        else
            null;
        errdefer if (name) |n| allocator.free(n);

        // Parse status effect icon
        const status_icon: ?[]const u8 = if (json.getStringField(obj, "StatusEffectIcon")) |s|
            try allocator.dupe(u8, s)
        else
            null;
        errdefer if (status_icon) |s| allocator.free(s);

        // Parse overlap behavior
        const overlap = if (json.getStringField(obj, "OverlapBehavior")) |s|
            OverlapBehavior.fromString(s)
        else
            DEFAULTS.overlap_behavior;

        // Parse value type
        const value_type = if (json.getStringField(obj, "ValueType")) |s|
            ValueType.fromString(s)
        else
            DEFAULTS.value_type;

        // Parse stat modifiers from EntityStats or StatModifiers field
        // This is a Map<String, Float> in JSON that gets resolved to Map<Integer, Float> indices
        // For now we'll store the raw values; the indices would need entity stat type registry
        var stat_mods: ?[]StatModifier = null;
        if (json.getObjectField(obj, "EntityStats") orelse json.getObjectField(obj, "StatModifiers")) |stats_obj| {
            var mods: std.ArrayList(StatModifier) = .empty;
            errdefer mods.deinit(allocator);

            var stats_iter = stats_obj.iterator();
            while (stats_iter.next()) |entry| {
                // Key is stat name (would need to resolve to index via EntityStatType registry)
                // For now, use a hash as a placeholder index
                const hash_u64 = std.hash.Wyhash.hash(0, entry.key_ptr.*);
                const key_hash: i32 = @bitCast(@as(u32, @truncate(hash_u64)));

                const value: f32 = switch (entry.value_ptr.*) {
                    .float => |f| @floatCast(f),
                    .integer => |i| @floatFromInt(i),
                    else => continue,
                };

                try mods.append(allocator, .{ .key = key_hash, .value = value });
            }

            if (mods.items.len > 0) {
                stat_mods = try mods.toOwnedSlice(allocator);
            }
        }
        errdefer if (stat_mods) |sm| allocator.free(sm);

        return .{
            .id = try allocator.dupe(u8, id),
            .name = name,
            .world_removal_sound_index = 0, // Would need SoundEvent registry to resolve
            .local_removal_sound_index = 0, // Would need SoundEvent registry to resolve
            .duration = json.getNumberFieldF32(obj, "Duration") orelse DEFAULTS.duration,
            .infinite = json.getBoolField(obj, "Infinite") orelse DEFAULTS.infinite,
            .debuff = json.getBoolField(obj, "Debuff") orelse DEFAULTS.debuff,
            .overlap_behavior = overlap,
            .damage_calculator_cooldown = blk: {
                const cooldown = json.getNumberFieldF32(obj, "DamageCalculatorCooldown") orelse 0;
                break :blk @floatCast(cooldown);
            },
            .value_type = value_type,
            .status_effect_icon = status_icon,
            .stat_modifiers = stat_mods,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.name) |n| allocator.free(n);
        if (self.status_effect_icon) |s| allocator.free(s);
        if (self.stat_modifiers) |sm| allocator.free(sm);
    }
};

test "EntityEffectAsset defaults" {
    const allocator = std.testing.allocator;
    const content = "{}";

    var asset = try EntityEffectAsset.parseJson(allocator, "test_effect", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("test_effect", asset.id);
    try std.testing.expectEqual(EntityEffectAsset.DEFAULTS.duration, asset.duration);
    try std.testing.expectEqual(EntityEffectAsset.DEFAULTS.infinite, asset.infinite);
    try std.testing.expectEqual(EntityEffectAsset.DEFAULTS.debuff, asset.debuff);
    try std.testing.expectEqual(EntityEffectAsset.DEFAULTS.overlap_behavior, asset.overlap_behavior);
    try std.testing.expectEqual(EntityEffectAsset.DEFAULTS.value_type, asset.value_type);
}

test "EntityEffectAsset with values" {
    const allocator = std.testing.allocator;
    const content =
        \\{
        \\  "Name": "effects.poison",
        \\  "Duration": 10.5,
        \\  "Infinite": false,
        \\  "Debuff": true,
        \\  "OverlapBehavior": "Extend",
        \\  "ValueType": "Percent",
        \\  "StatusEffectIcon": "icons/poison.png",
        \\  "DamageCalculatorCooldown": 0.5
        \\}
    ;

    var asset = try EntityEffectAsset.parseJson(allocator, "poison_effect", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("poison_effect", asset.id);
    try std.testing.expectEqualStrings("effects.poison", asset.name.?);
    try std.testing.expectApproxEqRel(@as(f32, 10.5), asset.duration, 0.001);
    try std.testing.expectEqual(false, asset.infinite);
    try std.testing.expectEqual(true, asset.debuff);
    try std.testing.expectEqual(OverlapBehavior.extend, asset.overlap_behavior);
    try std.testing.expectEqual(ValueType.percent, asset.value_type);
    try std.testing.expectEqualStrings("icons/poison.png", asset.status_effect_icon.?);
    try std.testing.expectApproxEqRel(@as(f64, 0.5), asset.damage_calculator_cooldown, 0.001);
}

test "OverlapBehavior fromString" {
    try std.testing.expectEqual(OverlapBehavior.extend, OverlapBehavior.fromString("Extend"));
    try std.testing.expectEqual(OverlapBehavior.extend, OverlapBehavior.fromString("EXTEND"));
    try std.testing.expectEqual(OverlapBehavior.overwrite, OverlapBehavior.fromString("Overwrite"));
    try std.testing.expectEqual(OverlapBehavior.ignore, OverlapBehavior.fromString("Ignore"));
    try std.testing.expectEqual(OverlapBehavior.ignore, OverlapBehavior.fromString("unknown"));
}

test "ValueType fromString" {
    try std.testing.expectEqual(ValueType.percent, ValueType.fromString("Percent"));
    try std.testing.expectEqual(ValueType.percent, ValueType.fromString("PERCENT"));
    try std.testing.expectEqual(ValueType.absolute, ValueType.fromString("Absolute"));
    try std.testing.expectEqual(ValueType.absolute, ValueType.fromString("unknown"));
}
