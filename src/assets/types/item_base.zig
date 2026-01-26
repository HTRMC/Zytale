/// ItemBase Asset Type
///
/// Represents item definitions with all their properties.
/// Protocol: NULLABLE_BIT_FIELD_SIZE=4, FIXED_BLOCK_SIZE=147, VARIABLE_FIELD_COUNT=26, VARIABLE_BLOCK_START=251

const std = @import("std");
const Allocator = std.mem.Allocator;
const item_player_animations = @import("item_player_animations.zig");
const projectile_config = @import("projectile_config.zig");

// Re-exports
pub const Vector3f = item_player_animations.Vector3f;
pub const ItemPullbackConfiguration = item_player_animations.ItemPullbackConfiguration;
pub const ColorLight = projectile_config.ColorLight;
pub const InteractionType = projectile_config.InteractionType;

// Helper functions
fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeF64(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f64) !void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeI32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &bytes, value, .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeVarInt(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var vi_buf: [5]u8 = undefined;
    var v: u32 = @bitCast(value);
    var i: usize = 0;
    while (v >= 0x80) : (i += 1) {
        vi_buf[i] = @truncate((v & 0x7F) | 0x80);
        v >>= 7;
    }
    vi_buf[i] = @truncate(v);
    try buf.appendSlice(allocator, vi_buf[0 .. i + 1]);
}

fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    try writeVarInt(buf, allocator, @intCast(str.len));
    try buf.appendSlice(allocator, str);
}

// ============================================================================
// Enums
// ============================================================================

pub const ModifierTarget = enum(u8) {
    min = 0,
    max = 1,
};

pub const CalculationType = enum(u8) {
    additive = 0,
    multiplicative = 1,
};

pub const ItemArmorSlot = enum(u8) {
    head = 0,
    chest = 1,
    hands = 2,
    legs = 3,
};

pub const Cosmetic = enum(u8) {
    haircut = 0,
    facial_hair = 1,
    undertop = 2,
    overtop = 3,
    pants = 4,
    overpants = 5,
    shoes = 6,
    gloves = 7,
    cape = 8,
    head_accessory = 9,
    face_accessory = 10,
    ear_accessory = 11,
    ear = 12,
};

pub const EntityPart = enum(u8) {
    self = 0,
    entity = 1,
    primary_item = 2,
    secondary_item = 3,
};

pub const GameMode = enum(u8) {
    adventure = 0,
    creative = 1,
};

pub const PrioritySlot = enum(u8) {
    slot0 = 0,
    slot1 = 1,
    slot2 = 2,
    slot3 = 3,
};

pub const ValueType = enum(u8) {
    percent = 0,
    absolute = 1,
};

// ============================================================================
// Basic Structs
// ============================================================================

/// Color (3 bytes)
pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    pub const SIZE: usize = 3;

    pub fn serialize(self: Color, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.r);
        try buf.append(allocator, self.g);
        try buf.append(allocator, self.b);
    }
};

/// Vector2f (8 bytes)
pub const Vector2f = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub const SIZE: usize = 8;

    pub fn serialize(self: Vector2f, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.x);
        try writeF32(buf, allocator, self.y);
    }
};

/// Direction (12 bytes) - same as Vector3f
pub const Direction = Vector3f;

/// FloatRange (8 bytes)
pub const FloatRange = struct {
    min: f32 = 0.0,
    max: f32 = 0.0,

    pub const SIZE: usize = 8;

    pub fn serialize(self: FloatRange, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.min);
        try writeF32(buf, allocator, self.max);
    }
};

/// Modifier (6 bytes fixed, no nullBits)
pub const Modifier = struct {
    target: ModifierTarget = .min,
    calculation_type: CalculationType = .additive,
    amount: f32 = 0.0,

    pub const SIZE: usize = 6;

    pub fn serialize(self: Modifier, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, @intFromEnum(self.target));
        try buf.append(allocator, @intFromEnum(self.calculation_type));
        try writeF32(buf, allocator, self.amount);
    }
};

// ============================================================================
// Nested Item Types
// ============================================================================

/// AssetIconProperties (25 bytes fixed, inline)
pub const AssetIconProperties = struct {
    scale: f32 = 1.0,
    translation: ?Vector2f = null,
    rotation: ?Vector3f = null,

    pub const SIZE: usize = 25;

    pub fn serialize(self: AssetIconProperties, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.translation != null) null_bits |= 0x01;
        if (self.rotation != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // scale
        try writeF32(buf, allocator, self.scale);

        // translation (8 bytes, always written)
        if (self.translation) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 8);
        }

        // rotation (12 bytes, always written)
        if (self.rotation) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }
    }
};

/// ItemGlider (16 bytes fixed, no nullBits, inline)
pub const ItemGlider = struct {
    terminal_velocity: f32 = 0.0,
    fall_speed_multiplier: f32 = 0.0,
    horizontal_speed_multiplier: f32 = 0.0,
    speed: f32 = 0.0,

    pub const SIZE: usize = 16;

    pub fn serialize(self: ItemGlider, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.terminal_velocity);
        try writeF32(buf, allocator, self.fall_speed_multiplier);
        try writeF32(buf, allocator, self.horizontal_speed_multiplier);
        try writeF32(buf, allocator, self.speed);
    }
};

/// BlockSelectorToolData (4 bytes fixed, no nullBits, inline)
pub const BlockSelectorToolData = struct {
    durability_loss_on_use: f32 = 0.0,

    pub const SIZE: usize = 4;

    pub fn serialize(self: BlockSelectorToolData, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeF32(buf, allocator, self.durability_loss_on_use);
    }
};

/// ItemToolSpec (9 bytes fixed + inline variable)
pub const ItemToolSpec = struct {
    gather_type: ?[]const u8 = null,
    power: f32 = 0.0,
    quality: i32 = 0,

    pub fn serialize(self: ItemToolSpec, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.gather_type != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // power
        try writeF32(buf, allocator, self.power);

        // quality
        try writeI32(buf, allocator, self.quality);

        // gatherType (inline variable)
        if (self.gather_type) |gt| {
            try writeVarString(buf, allocator, gt);
        }
    }
};

/// ItemTool (5 bytes fixed + inline variable)
pub const ItemTool = struct {
    specs: ?[]const ItemToolSpec = null,
    speed: f32 = 0.0,

    pub fn serialize(self: ItemTool, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.specs != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // speed
        try writeF32(buf, allocator, self.speed);

        // specs (inline variable)
        if (self.specs) |specs| {
            try writeVarInt(buf, allocator, @intCast(specs.len));
            for (specs) |spec| {
                try spec.serialize(buf, allocator);
            }
        }
    }
};

/// Modifier map entry (int key -> Modifier[] value)
pub const StatModifierEntry = struct {
    key: i32,
    modifiers: []const Modifier,
};

/// ItemWeapon (10 bytes fixed + offset-based variable)
pub const ItemWeapon = struct {
    entity_stats_to_clear: ?[]const i32 = null,
    stat_modifiers: ?[]const StatModifierEntry = null,
    render_dual_wielded: bool = false,

    pub const VARIABLE_BLOCK_START: usize = 10;

    pub fn serialize(self: ItemWeapon, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.entity_stats_to_clear != null) null_bits |= 0x01;
        if (self.stat_modifiers != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // renderDualWielded
        try buf.append(allocator, if (self.render_dual_wielded) @as(u8, 1) else 0);

        // Reserve offset slots
        const entity_stats_offset_pos = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
        const stat_modifiers_offset_pos = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = buf.items.len;

        // entityStatsToClear
        if (self.entity_stats_to_clear) |stats| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[entity_stats_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(stats.len));
            for (stats) |stat| {
                try writeI32(buf, allocator, stat);
            }
        } else {
            std.mem.writeInt(i32, buf.items[entity_stats_offset_pos..][0..4], -1, .little);
        }

        // statModifiers
        if (self.stat_modifiers) |modifiers| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[stat_modifiers_offset_pos..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(modifiers.len));
            for (modifiers) |entry| {
                try writeI32(buf, allocator, entry.key);
                try writeVarInt(buf, allocator, @intCast(entry.modifiers.len));
                for (entry.modifiers) |mod| {
                    try mod.serialize(buf, allocator);
                }
            }
        } else {
            std.mem.writeInt(i32, buf.items[stat_modifiers_offset_pos..][0..4], -1, .little);
        }
    }
};

/// String key modifier entry
pub const StringModifierEntry = struct {
    key: []const u8,
    modifiers: []const Modifier,
};

/// ItemArmor (30 bytes fixed + offset-based variable)
pub const ItemArmor = struct {
    armor_slot: ItemArmorSlot = .head,
    cosmetics_to_hide: ?[]const Cosmetic = null,
    stat_modifiers: ?[]const StatModifierEntry = null,
    base_damage_resistance: f64 = 0.0,
    damage_resistance: ?[]const StringModifierEntry = null,
    damage_enhancement: ?[]const StringModifierEntry = null,
    damage_class_enhancement: ?[]const StringModifierEntry = null,

    pub const VARIABLE_BLOCK_START: usize = 30;

    pub fn serialize(self: ItemArmor, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.cosmetics_to_hide != null) null_bits |= 0x01;
        if (self.stat_modifiers != null) null_bits |= 0x02;
        if (self.damage_resistance != null) null_bits |= 0x04;
        if (self.damage_enhancement != null) null_bits |= 0x08;
        if (self.damage_class_enhancement != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // armorSlot
        try buf.append(allocator, @intFromEnum(self.armor_slot));

        // baseDamageResistance
        try writeF64(buf, allocator, self.base_damage_resistance);

        // Reserve 5 offset slots (20 bytes)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 20);

        const var_block_start = buf.items.len;

        // cosmeticsToHide
        if (self.cosmetics_to_hide) |cosmetics| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(cosmetics.len));
            for (cosmetics) |c| {
                try buf.append(allocator, @intFromEnum(c));
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // statModifiers
        if (self.stat_modifiers) |modifiers| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(modifiers.len));
            for (modifiers) |entry| {
                try writeI32(buf, allocator, entry.key);
                try writeVarInt(buf, allocator, @intCast(entry.modifiers.len));
                for (entry.modifiers) |mod| {
                    try mod.serialize(buf, allocator);
                }
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }

        // damageResistance
        if (self.damage_resistance) |entries| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(entries.len));
            for (entries) |entry| {
                try writeVarString(buf, allocator, entry.key);
                try writeVarInt(buf, allocator, @intCast(entry.modifiers.len));
                for (entry.modifiers) |mod| {
                    try mod.serialize(buf, allocator);
                }
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], -1, .little);
        }

        // damageEnhancement
        if (self.damage_enhancement) |entries| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(entries.len));
            for (entries) |entry| {
                try writeVarString(buf, allocator, entry.key);
                try writeVarInt(buf, allocator, @intCast(entry.modifiers.len));
                for (entry.modifiers) |mod| {
                    try mod.serialize(buf, allocator);
                }
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], -1, .little);
        }

        // damageClassEnhancement
        if (self.damage_class_enhancement) |entries| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(entries.len));
            for (entries) |entry| {
                try writeVarString(buf, allocator, entry.key);
                try writeVarInt(buf, allocator, @intCast(entry.modifiers.len));
                for (entry.modifiers) |mod| {
                    try mod.serialize(buf, allocator);
                }
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], -1, .little);
        }
    }
};

/// ItemUtility (11 bytes fixed + offset-based variable)
pub const ItemUtility = struct {
    usable: bool = false,
    compatible: bool = false,
    entity_stats_to_clear: ?[]const i32 = null,
    stat_modifiers: ?[]const StatModifierEntry = null,

    pub const VARIABLE_BLOCK_START: usize = 11;

    pub fn serialize(self: ItemUtility, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.entity_stats_to_clear != null) null_bits |= 0x01;
        if (self.stat_modifiers != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // usable, compatible
        try buf.append(allocator, if (self.usable) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.compatible) @as(u8, 1) else 0);

        // Reserve offset slots
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 8);

        const var_block_start = buf.items.len;

        // entityStatsToClear
        if (self.entity_stats_to_clear) |stats| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(stats.len));
            for (stats) |stat| {
                try writeI32(buf, allocator, stat);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // statModifiers
        if (self.stat_modifiers) |modifiers| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(modifiers.len));
            for (modifiers) |entry| {
                try writeI32(buf, allocator, entry.key);
                try writeVarInt(buf, allocator, @intCast(entry.modifiers.len));
                for (entry.modifiers) |mod| {
                    try mod.serialize(buf, allocator);
                }
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }
    }
};

/// ItemTranslationProperties (9 bytes fixed + offset-based variable)
pub const ItemTranslationProperties = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,

    pub const VARIABLE_BLOCK_START: usize = 9;

    pub fn serialize(self: ItemTranslationProperties, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.name != null) null_bits |= 0x01;
        if (self.description != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Reserve offset slots
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 8);

        const var_block_start = buf.items.len;

        // name
        if (self.name) |n| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarString(buf, allocator, n);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // description
        if (self.description) |d| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarString(buf, allocator, d);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }
    }
};

/// ItemResourceType (5 bytes fixed + inline variable)
pub const ItemResourceType = struct {
    id: ?[]const u8 = null,
    quantity: i32 = 1,

    pub fn serialize(self: ItemResourceType, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // quantity
        try writeI32(buf, allocator, self.quantity);

        // id (inline variable)
        if (self.id) |id| {
            try writeVarString(buf, allocator, id);
        }
    }
};

/// ModelParticle (42 bytes fixed + offset-based variable)
pub const ModelParticle = struct {
    system_id: ?[]const u8 = null,
    scale: f32 = 1.0,
    color: ?Color = null,
    target_entity_part: EntityPart = .self,
    target_node_name: ?[]const u8 = null,
    position_offset: ?Vector3f = null,
    rotation_offset: ?Direction = null,
    detached_from_model: bool = false,

    pub const VARIABLE_BLOCK_START: usize = 42;

    pub fn serialize(self: ModelParticle, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.color != null) null_bits |= 0x01;
        if (self.position_offset != null) null_bits |= 0x02;
        if (self.rotation_offset != null) null_bits |= 0x04;
        if (self.system_id != null) null_bits |= 0x08;
        if (self.target_node_name != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // scale
        try writeF32(buf, allocator, self.scale);

        // color (3 bytes, always written)
        if (self.color) |c| {
            try c.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 3);
        }

        // targetEntityPart
        try buf.append(allocator, @intFromEnum(self.target_entity_part));

        // positionOffset (12 bytes, always written)
        if (self.position_offset) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // rotationOffset (12 bytes, always written)
        if (self.rotation_offset) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // detachedFromModel
        try buf.append(allocator, if (self.detached_from_model) @as(u8, 1) else 0);

        // Reserve offset slots
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 8);

        const var_block_start = buf.items.len;

        // systemId
        if (self.system_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarString(buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // targetNodeName
        if (self.target_node_name) |name| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarString(buf, allocator, name);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }
    }
};

/// ModelTrail (35 bytes fixed + offset-based variable)
pub const ModelTrail = struct {
    trail_id: ?[]const u8 = null,
    target_entity_part: EntityPart = .self,
    target_node_name: ?[]const u8 = null,
    position_offset: ?Vector3f = null,
    rotation_offset: ?Direction = null,
    fixed_rotation: bool = false,

    pub const VARIABLE_BLOCK_START: usize = 35;

    pub fn serialize(self: ModelTrail, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.position_offset != null) null_bits |= 0x01;
        if (self.rotation_offset != null) null_bits |= 0x02;
        if (self.trail_id != null) null_bits |= 0x04;
        if (self.target_node_name != null) null_bits |= 0x08;
        try buf.append(allocator, null_bits);

        // targetEntityPart
        try buf.append(allocator, @intFromEnum(self.target_entity_part));

        // positionOffset (12 bytes, always written)
        if (self.position_offset) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // rotationOffset (12 bytes, always written)
        if (self.rotation_offset) |v| {
            try v.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // fixedRotation
        try buf.append(allocator, if (self.fixed_rotation) @as(u8, 1) else 0);

        // Reserve offset slots
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 8);

        const var_block_start = buf.items.len;

        // trailId
        if (self.trail_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarString(buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // targetNodeName
        if (self.target_node_name) |name| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarString(buf, allocator, name);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }
    }
};

/// ItemEntityConfig (5 bytes fixed + inline variable)
pub const ItemEntityConfig = struct {
    particle_system_id: ?[]const u8 = null,
    particle_color: ?Color = null,
    show_item_particles: bool = false,

    pub fn serialize(self: ItemEntityConfig, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.particle_color != null) null_bits |= 0x01;
        if (self.particle_system_id != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // particleColor (3 bytes, always written)
        if (self.particle_color) |c| {
            try c.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 3);
        }

        // showItemParticles
        try buf.append(allocator, if (self.show_item_particles) @as(u8, 1) else 0);

        // particleSystemId (inline variable)
        if (self.particle_system_id) |id| {
            try writeVarString(buf, allocator, id);
        }
    }
};

/// ItemBuilderToolData (9 bytes fixed + offset-based variable)
/// Simplified - BuilderToolState serialization not fully implemented
pub const ItemBuilderToolData = struct {
    ui: ?[]const []const u8 = null,

    pub const VARIABLE_BLOCK_START: usize = 9;

    pub fn serialize(self: ItemBuilderToolData, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.ui != null) null_bits |= 0x01;
        // tools not implemented
        try buf.append(allocator, null_bits);

        // Reserve offset slots
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 8);

        const var_block_start = buf.items.len;

        // ui
        if (self.ui) |ui_items| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(ui_items.len));
            for (ui_items) |item| {
                try writeVarString(buf, allocator, item);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // tools offset = -1 (not implemented)
        std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
    }
};

/// InteractionConfiguration (12 bytes fixed + offset-based variable)
/// Simplified - complex maps not fully implemented
pub const InteractionConfiguration = struct {
    display_outlines: bool = true,
    debug_outlines: bool = false,
    all_entities: bool = false,

    pub const VARIABLE_BLOCK_START: usize = 12;

    pub fn serialize(self: InteractionConfiguration, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits (no variable fields present in simplified version)
        try buf.append(allocator, 0);

        // displayOutlines, debugOutlines, allEntities
        try buf.append(allocator, if (self.display_outlines) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.debug_outlines) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.all_entities) @as(u8, 1) else 0);

        // Offset slots = -1 (fields not present)
        try buf.appendSlice(allocator, &[_]u8{ 0xff, 0xff, 0xff, 0xff }); // useDistance offset
        try buf.appendSlice(allocator, &[_]u8{ 0xff, 0xff, 0xff, 0xff }); // priorities offset
    }
};

/// Interaction entry (InteractionType key -> i32 value)
pub const InteractionEntry = struct {
    interaction_type: InteractionType,
    value: i32,
};

/// InteractionVar entry (string key -> i32 value)
pub const InteractionVarEntry = struct {
    key: []const u8,
    value: i32,
};

// ============================================================================
// ItemBaseAsset
// ============================================================================

/// ItemBase asset (147 bytes fixed + 104 offset bytes = 251 total, 26 variable fields)
pub const ItemBaseAsset = struct {
    const Self = @This();

    // Variable fields
    id: ?[]const u8 = null,
    model: ?[]const u8 = null,
    texture: ?[]const u8 = null,
    animation: ?[]const u8 = null,
    player_animations_id: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    translation_properties: ?ItemTranslationProperties = null,
    resource_types: ?[]const ItemResourceType = null,
    tool: ?ItemTool = null,
    weapon: ?ItemWeapon = null,
    armor: ?ItemArmor = null,
    utility: ?ItemUtility = null,
    builder_tool_data: ?ItemBuilderToolData = null,
    item_entity: ?ItemEntityConfig = null,
    set: ?[]const u8 = null,
    categories: ?[]const []const u8 = null,
    particles: ?[]const ModelParticle = null,
    first_person_particles: ?[]const ModelParticle = null,
    trails: ?[]const ModelTrail = null,
    interactions: ?[]const InteractionEntry = null,
    interaction_vars: ?[]const InteractionVarEntry = null,
    interaction_config: ?InteractionConfiguration = null,
    dropped_item_animation: ?[]const u8 = null,
    tag_indexes: ?[]const i32 = null,
    // itemAppearanceConditions - complex, not implemented
    display_entity_stats_hud: ?[]const i32 = null,

    // Fixed (inline) fields
    scale: f32 = 1.0,
    use_player_animations: bool = false,
    max_stack: i32 = 1,
    reticle_index: i32 = 0,
    icon_properties: ?AssetIconProperties = null,
    item_level: i32 = 0,
    quality_index: i32 = 0,
    consumable: bool = false,
    variant: bool = false,
    block_id: i32 = 0,
    glider_config: ?ItemGlider = null,
    block_selector_tool: ?BlockSelectorToolData = null,
    light: ?ColorLight = null,
    durability: f64 = 0.0,
    sound_event_index: i32 = 0,
    item_sound_set_index: i32 = 0,
    pullback_config: ?ItemPullbackConfiguration = null,
    clips_geometry: bool = false,
    render_deployable_preview: bool = false,

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 4;
    pub const FIXED_BLOCK_SIZE: u32 = 147;
    pub const VARIABLE_FIELD_COUNT: u32 = 26;
    pub const VARIABLE_BLOCK_START: u32 = 251;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Build nullBits (4 bytes)
        var null_bits: [4]u8 = .{ 0, 0, 0, 0 };

        // Byte 0: inline nullable fields + first variable fields
        if (self.icon_properties != null) null_bits[0] |= 0x01;
        if (self.glider_config != null) null_bits[0] |= 0x02;
        if (self.block_selector_tool != null) null_bits[0] |= 0x04;
        if (self.light != null) null_bits[0] |= 0x08;
        if (self.pullback_config != null) null_bits[0] |= 0x10;
        if (self.id != null) null_bits[0] |= 0x20;
        if (self.model != null) null_bits[0] |= 0x40;
        if (self.texture != null) null_bits[0] |= 0x80;

        // Byte 1
        if (self.animation != null) null_bits[1] |= 0x01;
        if (self.player_animations_id != null) null_bits[1] |= 0x02;
        if (self.icon != null) null_bits[1] |= 0x04;
        if (self.translation_properties != null) null_bits[1] |= 0x08;
        if (self.resource_types != null) null_bits[1] |= 0x10;
        if (self.tool != null) null_bits[1] |= 0x20;
        if (self.weapon != null) null_bits[1] |= 0x40;
        if (self.armor != null) null_bits[1] |= 0x80;

        // Byte 2
        if (self.utility != null) null_bits[2] |= 0x01;
        if (self.builder_tool_data != null) null_bits[2] |= 0x02;
        if (self.item_entity != null) null_bits[2] |= 0x04;
        if (self.set != null) null_bits[2] |= 0x08;
        if (self.categories != null) null_bits[2] |= 0x10;
        if (self.particles != null) null_bits[2] |= 0x20;
        if (self.first_person_particles != null) null_bits[2] |= 0x40;
        if (self.trails != null) null_bits[2] |= 0x80;

        // Byte 3
        if (self.interactions != null) null_bits[3] |= 0x01;
        if (self.interaction_vars != null) null_bits[3] |= 0x02;
        if (self.interaction_config != null) null_bits[3] |= 0x04;
        if (self.dropped_item_animation != null) null_bits[3] |= 0x08;
        if (self.tag_indexes != null) null_bits[3] |= 0x10;
        // itemAppearanceConditions not implemented (bit 5)
        if (self.display_entity_stats_hud != null) null_bits[3] |= 0x40;

        try buf.appendSlice(allocator, &null_bits);

        // Fixed block fields
        try writeF32(&buf, allocator, self.scale);
        try buf.append(allocator, if (self.use_player_animations) @as(u8, 1) else 0);
        try writeI32(&buf, allocator, self.max_stack);
        try writeI32(&buf, allocator, self.reticle_index);

        // iconProperties (25 bytes, always written)
        if (self.icon_properties) |ip| {
            try ip.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 25);
        }

        try writeI32(&buf, allocator, self.item_level);
        try writeI32(&buf, allocator, self.quality_index);
        try buf.append(allocator, if (self.consumable) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.variant) @as(u8, 1) else 0);
        try writeI32(&buf, allocator, self.block_id);

        // gliderConfig (16 bytes, always written)
        if (self.glider_config) |gc| {
            try gc.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 16);
        }

        // blockSelectorTool (4 bytes, always written)
        if (self.block_selector_tool) |bst| {
            try bst.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 4);
        }

        // light (4 bytes, always written)
        if (self.light) |l| {
            try l.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 4);
        }

        try writeF64(&buf, allocator, self.durability);
        try writeI32(&buf, allocator, self.sound_event_index);
        try writeI32(&buf, allocator, self.item_sound_set_index);

        // pullbackConfig (49 bytes, always written)
        if (self.pullback_config) |pc| {
            try pc.serialize(&buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 49);
        }

        try buf.append(allocator, if (self.clips_geometry) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.render_deployable_preview) @as(u8, 1) else 0);

        // Reserve 26 offset slots (104 bytes)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 104);

        const var_block_start = buf.items.len;

        // Helper to write string variable field
        const writeStringField = struct {
            fn f(b: *std.ArrayListUnmanaged(u8), alloc: Allocator, str: ?[]const u8, slot: usize, vbs: usize, os: usize) !void {
                if (str) |s| {
                    const offset: i32 = @intCast(b.items.len - vbs);
                    std.mem.writeInt(i32, b.items[os + slot * 4 ..][0..4], offset, .little);
                    try writeVarString(b, alloc, s);
                } else {
                    std.mem.writeInt(i32, b.items[os + slot * 4 ..][0..4], -1, .little);
                }
            }
        }.f;

        // Variable field 0: id
        try writeStringField(&buf, allocator, self.id, 0, var_block_start, offsets_start);

        // Variable field 1: model
        try writeStringField(&buf, allocator, self.model, 1, var_block_start, offsets_start);

        // Variable field 2: texture
        try writeStringField(&buf, allocator, self.texture, 2, var_block_start, offsets_start);

        // Variable field 3: animation
        try writeStringField(&buf, allocator, self.animation, 3, var_block_start, offsets_start);

        // Variable field 4: playerAnimationsId
        try writeStringField(&buf, allocator, self.player_animations_id, 4, var_block_start, offsets_start);

        // Variable field 5: icon
        try writeStringField(&buf, allocator, self.icon, 5, var_block_start, offsets_start);

        // Variable field 6: translationProperties
        if (self.translation_properties) |tp| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 6 * 4 ..][0..4], offset, .little);
            try tp.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 6 * 4 ..][0..4], -1, .little);
        }

        // Variable field 7: resourceTypes
        if (self.resource_types) |rts| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 7 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(rts.len));
            for (rts) |rt| {
                try rt.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 7 * 4 ..][0..4], -1, .little);
        }

        // Variable field 8: tool
        if (self.tool) |t| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 8 * 4 ..][0..4], offset, .little);
            try t.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 8 * 4 ..][0..4], -1, .little);
        }

        // Variable field 9: weapon
        if (self.weapon) |w| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 9 * 4 ..][0..4], offset, .little);
            try w.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 9 * 4 ..][0..4], -1, .little);
        }

        // Variable field 10: armor
        if (self.armor) |a| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 10 * 4 ..][0..4], offset, .little);
            try a.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 10 * 4 ..][0..4], -1, .little);
        }

        // Variable field 11: utility
        if (self.utility) |u| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 11 * 4 ..][0..4], offset, .little);
            try u.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 11 * 4 ..][0..4], -1, .little);
        }

        // Variable field 12: builderToolData
        if (self.builder_tool_data) |btd| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 12 * 4 ..][0..4], offset, .little);
            try btd.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 12 * 4 ..][0..4], -1, .little);
        }

        // Variable field 13: itemEntity
        if (self.item_entity) |ie| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 13 * 4 ..][0..4], offset, .little);
            try ie.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 13 * 4 ..][0..4], -1, .little);
        }

        // Variable field 14: set
        try writeStringField(&buf, allocator, self.set, 14, var_block_start, offsets_start);

        // Variable field 15: categories
        if (self.categories) |cats| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 15 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(cats.len));
            for (cats) |cat| {
                try writeVarString(&buf, allocator, cat);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 15 * 4 ..][0..4], -1, .little);
        }

        // Variable field 16: particles
        if (self.particles) |ps| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 16 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(ps.len));
            for (ps) |p| {
                try p.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 16 * 4 ..][0..4], -1, .little);
        }

        // Variable field 17: firstPersonParticles
        if (self.first_person_particles) |fps| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 17 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(fps.len));
            for (fps) |p| {
                try p.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 17 * 4 ..][0..4], -1, .little);
        }

        // Variable field 18: trails
        if (self.trails) |ts| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 18 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(ts.len));
            for (ts) |t| {
                try t.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 18 * 4 ..][0..4], -1, .little);
        }

        // Variable field 19: interactions (InteractionType -> i32)
        if (self.interactions) |ints| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 19 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(ints.len));
            for (ints) |entry| {
                try buf.append(allocator, @intFromEnum(entry.interaction_type));
                try writeI32(&buf, allocator, entry.value);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 19 * 4 ..][0..4], -1, .little);
        }

        // Variable field 20: interactionVars (string -> i32)
        if (self.interaction_vars) |ivs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 20 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(ivs.len));
            for (ivs) |entry| {
                try writeVarString(&buf, allocator, entry.key);
                try writeI32(&buf, allocator, entry.value);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 20 * 4 ..][0..4], -1, .little);
        }

        // Variable field 21: interactionConfig
        if (self.interaction_config) |ic| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 21 * 4 ..][0..4], offset, .little);
            try ic.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 21 * 4 ..][0..4], -1, .little);
        }

        // Variable field 22: droppedItemAnimation
        try writeStringField(&buf, allocator, self.dropped_item_animation, 22, var_block_start, offsets_start);

        // Variable field 23: tagIndexes
        if (self.tag_indexes) |tis| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 23 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(tis.len));
            for (tis) |ti| {
                try writeI32(&buf, allocator, ti);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 23 * 4 ..][0..4], -1, .little);
        }

        // Variable field 24: itemAppearanceConditions (not implemented)
        std.mem.writeInt(i32, buf.items[offsets_start + 24 * 4 ..][0..4], -1, .little);

        // Variable field 25: displayEntityStatsHUD
        if (self.display_entity_stats_hud) |desh| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 25 * 4 ..][0..4], offset, .little);
            try writeVarInt(&buf, allocator, @intCast(desh.len));
            for (desh) |stat| {
                try writeI32(&buf, allocator, stat);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 25 * 4 ..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Create a simple item with defaults
    pub fn simple(id: ?[]const u8) Self {
        return .{
            .id = id,
            .scale = 1.0,
            .max_stack = 1,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ItemBaseAsset empty serialization" {
    const allocator = std.testing.allocator;
    const item = ItemBaseAsset{};
    const data = try item.serialize(allocator);
    defer allocator.free(data);

    // Should be at least VARIABLE_BLOCK_START bytes
    try std.testing.expect(data.len >= ItemBaseAsset.VARIABLE_BLOCK_START);
}

test "ItemBaseAsset with id" {
    const allocator = std.testing.allocator;
    const item = ItemBaseAsset.simple("test_item");
    const data = try item.serialize(allocator);
    defer allocator.free(data);

    // Check nullBits has id flag set
    try std.testing.expectEqual(@as(u8, 0x20), data[0] & 0x20);
}
