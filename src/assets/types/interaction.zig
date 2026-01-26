/// Interaction Asset Type
///
/// Represents interaction definitions for items/entities.
/// Polymorphic type with 44 subtypes (VarInt type ID prefix).
/// This implementation focuses on SimpleInteraction (type ID 1) which is the most common.

const std = @import("std");
const Allocator = std.mem.Allocator;
const item_base = @import("item_base.zig");
const projectile_config = @import("projectile_config.zig");

// Re-exports
pub const Vector3f = item_base.Vector3f;
pub const Direction = item_base.Direction;
pub const Color = item_base.Color;
pub const ModelParticle = item_base.ModelParticle;
pub const ModelTrail = item_base.ModelTrail;
pub const GameMode = item_base.GameMode;
pub const InteractionType = projectile_config.InteractionType;

// Helper functions
fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
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

pub const WaitForDataFrom = enum(u8) {
    client = 0,
    server = 1,
    none = 2,
};

pub const AccumulationMode = enum(u8) {
    set = 0,
    sum = 1,
    average = 2,
};

// ============================================================================
// Supporting Types
// ============================================================================

/// MovementEffects (7 bytes fixed, no nullBits)
pub const MovementEffects = struct {
    disable_forward: bool = false,
    disable_backward: bool = false,
    disable_left: bool = false,
    disable_right: bool = false,
    disable_sprint: bool = false,
    disable_jump: bool = false,
    disable_crouch: bool = false,

    pub const SIZE: usize = 7;

    pub fn serialize(self: MovementEffects, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, if (self.disable_forward) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.disable_backward) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.disable_left) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.disable_right) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.disable_sprint) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.disable_jump) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.disable_crouch) @as(u8, 1) else 0);
    }
};

/// CameraShakeEffect (9 bytes fixed, no nullBits)
pub const CameraShakeEffect = struct {
    camera_shake_id: i32 = 0,
    intensity: f32 = 0.0,
    mode: AccumulationMode = .set,

    pub const SIZE: usize = 9;

    pub fn serialize(self: CameraShakeEffect, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeI32(buf, allocator, self.camera_shake_id);
        try writeF32(buf, allocator, self.intensity);
        try buf.append(allocator, @intFromEnum(self.mode));
    }
};

/// InteractionCamera (29 bytes fixed)
pub const InteractionCamera = struct {
    time: f32 = 0.0,
    position: ?Vector3f = null,
    rotation: ?Direction = null,

    pub const SIZE: usize = 29;

    pub fn serialize(self: InteractionCamera, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.position != null) null_bits |= 0x01;
        if (self.rotation != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // time
        try writeF32(buf, allocator, self.time);

        // position (12 bytes, always written)
        if (self.position) |p| {
            try p.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }

        // rotation (12 bytes, always written)
        if (self.rotation) |r| {
            try r.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 12);
        }
    }
};

/// InteractionSettings (1 byte fixed, no nullBits)
pub const InteractionSettings = struct {
    allow_skip_on_click: bool = false,

    pub const SIZE: usize = 1;

    pub fn serialize(self: InteractionSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, if (self.allow_skip_on_click) @as(u8, 1) else 0);
    }
};

/// GameMode settings entry
pub const GameModeSettingsEntry = struct {
    mode: GameMode,
    settings: InteractionSettings,
};

/// InteractionRules (33 bytes minimum)
pub const InteractionRules = struct {
    blocked_by: ?[]const InteractionType = null,
    blocking: ?[]const InteractionType = null,
    interrupted_by: ?[]const InteractionType = null,
    interrupting: ?[]const InteractionType = null,
    blocked_by_bypass_index: i32 = 0,
    blocking_bypass_index: i32 = 0,
    interrupted_by_bypass_index: i32 = 0,
    interrupting_bypass_index: i32 = 0,

    pub const VARIABLE_BLOCK_START: usize = 33;

    pub fn serialize(self: InteractionRules, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.blocked_by != null) null_bits |= 0x01;
        if (self.blocking != null) null_bits |= 0x02;
        if (self.interrupted_by != null) null_bits |= 0x04;
        if (self.interrupting != null) null_bits |= 0x08;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeI32(buf, allocator, self.blocked_by_bypass_index);
        try writeI32(buf, allocator, self.blocking_bypass_index);
        try writeI32(buf, allocator, self.interrupted_by_bypass_index);
        try writeI32(buf, allocator, self.interrupting_bypass_index);

        // Reserve offset slots (16 bytes)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 16);

        const var_block_start = buf.items.len;

        // blocked_by
        if (self.blocked_by) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |t| {
                try buf.append(allocator, @intFromEnum(t));
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // blocking
        if (self.blocking) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |t| {
                try buf.append(allocator, @intFromEnum(t));
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }

        // interrupted_by
        if (self.interrupted_by) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |t| {
                try buf.append(allocator, @intFromEnum(t));
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], -1, .little);
        }

        // interrupting
        if (self.interrupting) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |t| {
                try buf.append(allocator, @intFromEnum(t));
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], -1, .little);
        }
    }
};

/// InteractionCameraSettings (9 bytes minimum)
pub const InteractionCameraSettings = struct {
    first_person: ?[]const InteractionCamera = null,
    third_person: ?[]const InteractionCamera = null,

    pub const VARIABLE_BLOCK_START: usize = 9;

    pub fn serialize(self: InteractionCameraSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.first_person != null) null_bits |= 0x01;
        if (self.third_person != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Reserve offset slots (8 bytes)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 8);

        const var_block_start = buf.items.len;

        // first_person
        if (self.first_person) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |cam| {
                try cam.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // third_person
        if (self.third_person) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |cam| {
                try cam.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }
    }
};

/// InteractionEffects (52 bytes minimum)
pub const InteractionEffects = struct {
    particles: ?[]const ModelParticle = null,
    first_person_particles: ?[]const ModelParticle = null,
    world_sound_event_index: i32 = 0,
    local_sound_event_index: i32 = 0,
    trails: ?[]const ModelTrail = null,
    wait_for_animation_to_finish: bool = true,
    item_player_animations_id: ?[]const u8 = null,
    item_animation_id: ?[]const u8 = null,
    clear_animation_on_finish: bool = false,
    clear_sound_event_on_finish: bool = false,
    camera_shake: ?CameraShakeEffect = null,
    movement_effects: ?MovementEffects = null,
    start_delay: f32 = 0.0,

    pub const VARIABLE_BLOCK_START: usize = 52;

    pub fn serialize(self: InteractionEffects, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.camera_shake != null) null_bits |= 0x01;
        if (self.movement_effects != null) null_bits |= 0x02;
        if (self.particles != null) null_bits |= 0x04;
        if (self.first_person_particles != null) null_bits |= 0x08;
        if (self.trails != null) null_bits |= 0x10;
        if (self.item_player_animations_id != null) null_bits |= 0x20;
        if (self.item_animation_id != null) null_bits |= 0x40;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeI32(buf, allocator, self.world_sound_event_index);
        try writeI32(buf, allocator, self.local_sound_event_index);
        try buf.append(allocator, if (self.wait_for_animation_to_finish) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.clear_animation_on_finish) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.clear_sound_event_on_finish) @as(u8, 1) else 0);

        // cameraShake (9 bytes, always written)
        if (self.camera_shake) |cs| {
            try cs.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 9);
        }

        // movementEffects (7 bytes, always written)
        if (self.movement_effects) |me| {
            try me.serialize(buf, allocator);
        } else {
            try buf.appendSlice(allocator, &[_]u8{0} ** 7);
        }

        try writeF32(buf, allocator, self.start_delay);

        // Reserve offset slots (20 bytes for 5 variable fields)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 20);

        const var_block_start = buf.items.len;

        // particles
        if (self.particles) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |p| {
                try p.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // first_person_particles
        if (self.first_person_particles) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |p| {
                try p.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }

        // trails
        if (self.trails) |arr| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(arr.len));
            for (arr) |t| {
                try t.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], -1, .little);
        }

        // item_player_animations_id
        if (self.item_player_animations_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], offset, .little);
            try writeVarString(buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], -1, .little);
        }

        // item_animation_id
        if (self.item_animation_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], offset, .little);
            try writeVarString(buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], -1, .little);
        }
    }
};

// ============================================================================
// Interaction Types
// ============================================================================

/// Interaction type IDs (polymorphic)
pub const InteractionTypeId = enum(u8) {
    simple_block = 0,
    simple = 1,
    place_block = 2,
    break_block = 3,
    pick_block = 4,
    use_block = 5,
    use_entity = 6,
    builder_tool = 7,
    modify_inventory = 8,
    charging = 9,
    wielding = 10,
    chaining = 11,
    condition = 12,
    stats_condition = 13,
    block_condition = 14,
    replace = 15,
    change_block = 16,
    change_state = 17,
    first_click = 18,
    // 19 is invalid
    select = 20,
    damage_entity = 21,
    repeat = 22,
    parallel = 23,
    change_active_slot = 24,
    effect_condition = 25,
    apply_force = 26,
    apply_effect = 27,
    clear_entity_effect = 28,
    serial = 29,
    change_stat = 30,
    movement_condition = 31,
    projectile = 32,
    remove_entity = 33,
    reset_cooldown = 34,
    trigger_cooldown = 35,
    cooldown_condition = 36,
    chain_flag = 37,
    increment_cooldown = 38,
    cancel_chain = 39,
    run_root = 40,
    camera = 41,
    spawn_deployable_from_raycast = 42,
    memories_condition = 43,
    toggle_glider = 44,
};

/// SimpleInteraction (type ID 1) - the most common interaction type
/// 39 bytes minimum (19 fixed + 20 offset bytes)
pub const SimpleInteraction = struct {
    // Base Interaction fields
    wait_for_data_from: WaitForDataFrom = .client,
    effects: ?InteractionEffects = null,
    horizontal_speed_multiplier: f32 = 0.0,
    run_time: f32 = 0.0,
    cancel_on_item_change: bool = false,
    settings: ?[]const GameModeSettingsEntry = null,
    rules: ?InteractionRules = null,
    tags: ?[]const i32 = null,
    camera: ?InteractionCameraSettings = null,

    // SimpleInteraction specific fields
    next: i32 = std.math.minInt(i32),
    failed: i32 = std.math.minInt(i32),

    pub const TYPE_ID: InteractionTypeId = .simple;
    pub const VARIABLE_BLOCK_START: usize = 39;

    pub fn serialize(self: SimpleInteraction, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.effects != null) null_bits |= 0x01;
        if (self.settings != null) null_bits |= 0x02;
        if (self.rules != null) null_bits |= 0x04;
        if (self.tags != null) null_bits |= 0x08;
        if (self.camera != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try buf.append(allocator, @intFromEnum(self.wait_for_data_from));
        try writeF32(buf, allocator, self.horizontal_speed_multiplier);
        try writeF32(buf, allocator, self.run_time);
        try buf.append(allocator, if (self.cancel_on_item_change) @as(u8, 1) else 0);
        try writeI32(buf, allocator, self.next);
        try writeI32(buf, allocator, self.failed);

        // Reserve offset slots (20 bytes for 5 variable fields)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 20);

        const var_block_start = buf.items.len;

        // effects
        if (self.effects) |eff| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try eff.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // settings (GameMode -> InteractionSettings)
        if (self.settings) |sets| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(sets.len));
            for (sets) |entry| {
                try buf.append(allocator, @intFromEnum(entry.mode));
                try entry.settings.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }

        // rules
        if (self.rules) |r| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], offset, .little);
            try r.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], -1, .little);
        }

        // tags
        if (self.tags) |t| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(t.len));
            for (t) |tag| {
                try writeI32(buf, allocator, tag);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], -1, .little);
        }

        // camera
        if (self.camera) |c| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], offset, .little);
            try c.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], -1, .little);
        }
    }
};

/// Polymorphic Interaction asset
/// Serialization: VarInt type ID + subtype data
pub const InteractionAsset = union(InteractionTypeId) {
    simple_block: SimpleInteraction, // Uses same structure as SimpleInteraction
    simple: SimpleInteraction,
    place_block: SimpleInteraction,
    break_block: SimpleInteraction,
    pick_block: SimpleInteraction,
    use_block: SimpleInteraction,
    use_entity: SimpleInteraction,
    builder_tool: SimpleInteraction,
    modify_inventory: SimpleInteraction,
    charging: SimpleInteraction,
    wielding: SimpleInteraction,
    chaining: SimpleInteraction,
    condition: SimpleInteraction,
    stats_condition: SimpleInteraction,
    block_condition: SimpleInteraction,
    replace: SimpleInteraction,
    change_block: SimpleInteraction,
    change_state: SimpleInteraction,
    first_click: SimpleInteraction,
    select: SimpleInteraction,
    damage_entity: SimpleInteraction,
    repeat: SimpleInteraction,
    parallel: SimpleInteraction,
    change_active_slot: SimpleInteraction,
    effect_condition: SimpleInteraction,
    apply_force: SimpleInteraction,
    apply_effect: SimpleInteraction,
    clear_entity_effect: SimpleInteraction,
    serial: SimpleInteraction,
    change_stat: SimpleInteraction,
    movement_condition: SimpleInteraction,
    projectile: SimpleInteraction,
    remove_entity: SimpleInteraction,
    reset_cooldown: SimpleInteraction,
    trigger_cooldown: SimpleInteraction,
    cooldown_condition: SimpleInteraction,
    chain_flag: SimpleInteraction,
    increment_cooldown: SimpleInteraction,
    cancel_chain: SimpleInteraction,
    run_root: SimpleInteraction,
    camera: SimpleInteraction,
    spawn_deployable_from_raycast: SimpleInteraction,
    memories_condition: SimpleInteraction,
    toggle_glider: SimpleInteraction,

    pub fn serialize(self: InteractionAsset, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Write type ID as VarInt
        const type_id: u8 = @intFromEnum(self);
        try writeVarInt(&buf, allocator, type_id);

        // Write subtype data (all use SimpleInteraction structure for now)
        const data = switch (self) {
            inline else => |si| si,
        };
        try data.serialize(&buf, allocator);

        return buf.toOwnedSlice(allocator);
    }

    /// Create a default simple interaction
    pub fn createSimple() InteractionAsset {
        return .{ .simple = .{} };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SimpleInteraction serialization" {
    const allocator = std.testing.allocator;
    const interaction = SimpleInteraction{};
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try interaction.serialize(&buf, allocator);

    // Should be at least VARIABLE_BLOCK_START bytes
    try std.testing.expect(buf.items.len >= SimpleInteraction.VARIABLE_BLOCK_START);
}

test "InteractionAsset serialization" {
    const allocator = std.testing.allocator;
    const int = InteractionAsset.createSimple();
    const data = try int.serialize(allocator);
    defer allocator.free(data);

    // First byte should be type ID 1 (simple)
    try std.testing.expectEqual(@as(u8, 1), data[0]);
}

// ============================================================================
// RootInteraction and supporting types
// ============================================================================

/// InteractionCooldown (16 bytes minimum)
pub const InteractionCooldown = struct {
    cooldown_id: ?[]const u8 = null,
    cooldown: f32 = 0.0,
    click_bypass: bool = false,
    charge_times: ?[]const f32 = null,
    skip_cooldown_reset: bool = false,
    interrupt_recharge: bool = false,

    pub const VARIABLE_BLOCK_START: usize = 16;

    pub fn serialize(self: InteractionCooldown, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.cooldown_id != null) null_bits |= 0x01;
        if (self.charge_times != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeF32(buf, allocator, self.cooldown);
        try buf.append(allocator, if (self.click_bypass) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.skip_cooldown_reset) @as(u8, 1) else 0);
        try buf.append(allocator, if (self.interrupt_recharge) @as(u8, 1) else 0);

        // Reserve offset slots (8 bytes)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 8);

        const var_block_start = buf.items.len;

        // cooldown_id
        if (self.cooldown_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarString(buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // charge_times
        if (self.charge_times) |times| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(times.len));
            for (times) |t| {
                try writeF32(buf, allocator, t);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }
    }
};

/// RootInteraction (30 bytes minimum)
/// Used by UpdateRootInteractions packet
pub const RootInteraction = struct {
    id: ?[]const u8 = null,
    interactions: ?[]const i32 = null,
    cooldown: ?InteractionCooldown = null,
    settings: ?[]const GameModeSettingsEntry = null,
    rules: ?InteractionRules = null,
    tags: ?[]const i32 = null,
    click_queuing_timeout: f32 = 0.0,
    require_new_click: bool = false,

    pub const VARIABLE_BLOCK_START: usize = 30;

    pub fn serialize(self: RootInteraction, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.interactions != null) null_bits |= 0x02;
        if (self.cooldown != null) null_bits |= 0x04;
        if (self.settings != null) null_bits |= 0x08;
        if (self.rules != null) null_bits |= 0x10;
        if (self.tags != null) null_bits |= 0x20;
        try buf.append(allocator, null_bits);

        // Fixed fields
        try writeF32(buf, allocator, self.click_queuing_timeout);
        try buf.append(allocator, if (self.require_new_click) @as(u8, 1) else 0);

        // Reserve offset slots (24 bytes for 6 variable fields)
        const offsets_start = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{0} ** 24);

        const var_block_start = buf.items.len;

        // id
        if (self.id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], offset, .little);
            try writeVarString(buf, allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start..][0..4], -1, .little);
        }

        // interactions
        if (self.interactions) |ints| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(ints.len));
            for (ints) |i| {
                try writeI32(buf, allocator, i);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 4 ..][0..4], -1, .little);
        }

        // cooldown
        if (self.cooldown) |c| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], offset, .little);
            try c.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 8 ..][0..4], -1, .little);
        }

        // settings
        if (self.settings) |sets| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(sets.len));
            for (sets) |entry| {
                try buf.append(allocator, @intFromEnum(entry.mode));
                try entry.settings.serialize(buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 12 ..][0..4], -1, .little);
        }

        // rules
        if (self.rules) |r| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], offset, .little);
            try r.serialize(buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 16 ..][0..4], -1, .little);
        }

        // tags
        if (self.tags) |t| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[offsets_start + 20 ..][0..4], offset, .little);
            try writeVarInt(buf, allocator, @intCast(t.len));
            for (t) |tag| {
                try writeI32(buf, allocator, tag);
            }
        } else {
            std.mem.writeInt(i32, buf.items[offsets_start + 20 ..][0..4], -1, .little);
        }
    }
};

test "RootInteraction serialization" {
    const allocator = std.testing.allocator;
    const root = RootInteraction{};
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try root.serialize(&buf, allocator);

    // Should be at least VARIABLE_BLOCK_START bytes
    try std.testing.expect(buf.items.len >= RootInteraction.VARIABLE_BLOCK_START);
}
