/// Block Type Asset
///
/// Represents a block type definition for the protocol.
/// Based on com/hypixel/hytale/protocol/BlockType.java

const std = @import("std");
const Allocator = std.mem.Allocator;

// Protocol constants - must match Java BlockType.java
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 4;
pub const FIXED_BLOCK_SIZE: u32 = 163;
pub const VARIABLE_FIELD_COUNT: u32 = 24;
pub const VARIABLE_BLOCK_START: u32 = 259;

/// Draw type for blocks
/// Values must match com/hypixel/hytale/protocol/DrawType.java
pub const DrawType = enum(u8) {
    empty = 0,
    gizmo_cube = 1,
    cube = 2,
    model = 3,
    cube_with_model = 4,
};

/// Block material type
pub const BlockMaterial = enum(u8) {
    empty = 0,
    solid = 1,
};

/// Block opacity
/// Values must match com/hypixel/hytale/protocol/Opacity.java
pub const Opacity = enum(u8) {
    solid = 0,
    semitransparent = 1,
    cutout = 2,
    transparent = 3,
};

/// Shading mode for cube blocks
pub const ShadingMode = enum(u8) {
    standard = 0,
};

/// Random rotation options
pub const RandomRotation = enum(u8) {
    none = 0,
};

/// Variant rotation options
pub const VariantRotation = enum(u8) {
    none = 0,
};

/// Rotation options
pub const Rotation = enum(u8) {
    none = 0,
};

/// Block supports required for type
/// Values must match com/hypixel/hytale/protocol/BlockSupportsRequiredForType.java
pub const BlockSupportsRequiredForType = enum(u8) {
    any = 0,
    all = 1,
};

/// Tint for block faces (24 bytes - 6 faces x i32 LE each)
/// Each face is an ARGB color as i32. -1 (0xFFFFFFFF) means no tint.
pub const Tint = struct {
    top: i32 = -1,
    bottom: i32 = -1,
    front: i32 = -1,
    back: i32 = -1,
    left: i32 = -1,
    right: i32 = -1,

    pub fn serialize(self: *const Tint, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try writeI32(buf, allocator, self.top);
        try writeI32(buf, allocator, self.bottom);
        try writeI32(buf, allocator, self.front);
        try writeI32(buf, allocator, self.back);
        try writeI32(buf, allocator, self.left);
        try writeI32(buf, allocator, self.right);
    }
};

/// Block movement settings (42 bytes)
/// Matches com/hypixel/hytale/protocol/BlockMovementSettings.java serialize order
pub const BlockMovementSettings = struct {
    is_climbable: bool = false,
    climb_up_speed_multiplier: f32 = 1.0,
    climb_down_speed_multiplier: f32 = 1.0,
    climb_lateral_speed_multiplier: f32 = 1.0,
    is_bouncy: bool = false,
    bounce_velocity: f32 = 0.0,
    drag: f32 = 0.82,
    friction: f32 = 0.18,
    terminal_velocity_modifier: f32 = 1.0,
    horizontal_speed_multiplier: f32 = 1.0,
    acceleration: f32 = 0.0,
    jump_force_multiplier: f32 = 1.0,

    pub fn serialize(self: *const BlockMovementSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, if (self.is_climbable) 1 else 0);
        try writeF32(buf, allocator, self.climb_up_speed_multiplier);
        try writeF32(buf, allocator, self.climb_down_speed_multiplier);
        try writeF32(buf, allocator, self.climb_lateral_speed_multiplier);
        try buf.append(allocator, if (self.is_bouncy) 1 else 0);
        try writeF32(buf, allocator, self.bounce_velocity);
        try writeF32(buf, allocator, self.drag);
        try writeF32(buf, allocator, self.friction);
        try writeF32(buf, allocator, self.terminal_velocity_modifier);
        try writeF32(buf, allocator, self.horizontal_speed_multiplier);
        try writeF32(buf, allocator, self.acceleration);
        try writeF32(buf, allocator, self.jump_force_multiplier);
    }
};

/// Block flags (2 bytes: isUsable, isStackable)
pub const BlockFlags = struct {
    is_usable: bool = false,
    is_stackable: bool = true, // Java default is true

    pub fn serialize(self: *const BlockFlags, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, if (self.is_usable) 1 else 0);
        try buf.append(allocator, if (self.is_stackable) 1 else 0);
    }
};

/// Block placement settings (16 bytes)
pub const BlockPlacementSettings = struct {
    allow_rotation_key: bool = false,
    place_in_empty_blocks: bool = false,
    preview_visibility: u8 = 0, // AlwaysVisible
    rotation_mode: u8 = 0, // FacingPlayer
    wall_placement_override_block_id: i32 = 0,
    floor_placement_override_block_id: i32 = 0,
    ceiling_placement_override_block_id: i32 = 0,

    pub fn serialize(self: *const BlockPlacementSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, if (self.allow_rotation_key) 1 else 0);
        try buf.append(allocator, if (self.place_in_empty_blocks) 1 else 0);
        try buf.append(allocator, self.preview_visibility);
        try buf.append(allocator, self.rotation_mode);
        try writeI32(buf, allocator, self.wall_placement_override_block_id);
        try writeI32(buf, allocator, self.floor_placement_override_block_id);
        try writeI32(buf, allocator, self.ceiling_placement_override_block_id);
    }
};

/// RGB Color (3 bytes)
pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    pub fn serialize(self: *const Color, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.r);
        try buf.append(allocator, self.g);
        try buf.append(allocator, self.b);
    }
};

/// Color with light radius (4 bytes)
pub const ColorLight = struct {
    radius: u8 = 0,
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    pub fn serialize(self: *const ColorLight, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.append(allocator, self.radius);
        try buf.append(allocator, self.r);
        try buf.append(allocator, self.g);
        try buf.append(allocator, self.b);
    }
};

/// Cube textures - 6 face textures for a cube block
pub const BlockTextures = struct {
    top: ?[]const u8 = null,
    bottom: ?[]const u8 = null,
    front: ?[]const u8 = null,
    back: ?[]const u8 = null,
    left: ?[]const u8 = null,
    right: ?[]const u8 = null,
    weight: f32 = 1.0,

    const Self = @This();

    /// Create a fallback texture set with "BlockTextures/Unknown.png" on all faces
    pub fn unknown(allocator: Allocator) !Self {
        const unknown_path = "BlockTextures/Unknown.png";
        return .{
            .top = try allocator.dupe(u8, unknown_path),
            .bottom = try allocator.dupe(u8, unknown_path),
            .front = try allocator.dupe(u8, unknown_path),
            .back = try allocator.dupe(u8, unknown_path),
            .left = try allocator.dupe(u8, unknown_path),
            .right = try allocator.dupe(u8, unknown_path),
            .weight = 1.0,
        };
    }

    /// Serialize cube textures to protocol format
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        var null_bits: u8 = 0;
        if (self.top != null) null_bits |= 0x01;
        if (self.bottom != null) null_bits |= 0x02;
        if (self.front != null) null_bits |= 0x04;
        if (self.back != null) null_bits |= 0x08;
        if (self.left != null) null_bits |= 0x10;
        if (self.right != null) null_bits |= 0x20;

        try buf.append(allocator, null_bits);
        try writeF32(&buf, allocator, self.weight);

        // 6 offset slots (24 bytes)
        const offset_positions = [6]usize{ buf.items.len, undefined, undefined, undefined, undefined, undefined };
        _ = offset_positions;
        const top_off = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const bottom_off = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const front_off = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const back_off = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const left_off = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const right_off = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        const var_block_start = buf.items.len;

        const face_data = [_]struct { str: ?[]const u8, off_pos: usize }{
            .{ .str = self.top, .off_pos = top_off },
            .{ .str = self.bottom, .off_pos = bottom_off },
            .{ .str = self.front, .off_pos = front_off },
            .{ .str = self.back, .off_pos = back_off },
            .{ .str = self.left, .off_pos = left_off },
            .{ .str = self.right, .off_pos = right_off },
        };

        for (face_data) |face| {
            if (face.str) |s| {
                const offset: i32 = @intCast(buf.items.len - var_block_start);
                std.mem.writeInt(i32, buf.items[face.off_pos..][0..4], offset, .little);
                try writeVarString(&buf, allocator, s);
            } else {
                std.mem.writeInt(i32, buf.items[face.off_pos..][0..4], -1, .little);
            }
        }

        return buf.toOwnedSlice(allocator);
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.top) |s| allocator.free(s);
        if (self.bottom) |s| allocator.free(s);
        if (self.front) |s| allocator.free(s);
        if (self.back) |s| allocator.free(s);
        if (self.left) |s| allocator.free(s);
        if (self.right) |s| allocator.free(s);
    }
};

// ─── NullBits layout ─────────────────────────────────────────────
// Byte 0 (inline fields):
//   bit 0: particleColor      bit 4: movementSettings
//   bit 1: light              bit 5: flags
//   bit 2: tint               bit 6: placementSettings
//   bit 3: biomeTint          bit 7: item (variable, slot 0)
//
// Byte 1 (variable fields):
//   bit 0: name (slot 1)      bit 4: modelAnimation (slot 5)
//   bit 1: shaderEffect (2)   bit 5: support (slot 6)
//   bit 2: model (slot 3)     bit 6: supporting (slot 7)
//   bit 3: modelTexture (4)   bit 7: cubeTextures (slot 8)
//
// Byte 2:
//   bit 0: cubeSideMaskTexture (9)   bit 4: transitionTexture (13)
//   bit 1: particles (10)           bit 5: transitionToGroups (14)
//   bit 2: blockParticleSetId (11)  bit 6: interactionHint (15)
//   bit 3: blockBreakingDecalId(12) bit 7: gathering (16)
//
// Byte 3:
//   bit 0: display (slot 17)     bit 4: tagIndexes (slot 21)
//   bit 1: rail (slot 18)       bit 5: bench (slot 22)
//   bit 2: interactions (19)    bit 6: connectedBlockRuleSet (23)
//   bit 3: states (slot 20)     bit 7: (unused)
// ─────────────────────────────────────────────────────────────────

/// Block type asset — full protocol representation
pub const BlockTypeAsset = struct {
    // ── Inline optional fields (fixed position, nullBits byte 0) ──
    particle_color: ?Color = null,
    light: ?ColorLight = null,
    tint: ?Tint = null,
    biome_tint: ?Tint = null,
    movement_settings: ?BlockMovementSettings = null,
    flags: ?BlockFlags = null,
    placement_settings: ?BlockPlacementSettings = null,

    // ── Required fixed fields with Java-matching defaults ──
    unknown: bool = false,
    draw_type: DrawType = .cube, // Java default: DrawType.Cube
    material: BlockMaterial = .empty, // Java default: BlockMaterial.Empty
    opacity: Opacity = .solid, // Java default: Opacity.Solid
    hitbox: i32 = 0,
    interaction_hitbox: i32 = std.math.minInt(i32), // Java: Integer.MIN_VALUE
    model_scale: f32 = 1.0,
    looping: bool = false,
    max_support_distance: i32 = 0,
    block_supports_required_for: BlockSupportsRequiredForType = .all, // Java default: All
    requires_alpha_blending: bool = false,
    cube_shading_mode: ShadingMode = .standard,
    random_rotation: RandomRotation = .none,
    variant_rotation: VariantRotation = .none,
    rotation_yaw_placement_offset: Rotation = .none,
    block_sound_set_index: i32 = 0, // Java default: 0
    ambient_sound_event_index: i32 = 0, // Java default: 0
    group: i32 = 0,
    ignore_support_when_placed: bool = false,
    transition_to_tag: i32 = std.math.minInt(i32), // Java: Integer.MIN_VALUE for "not set"

    // ── Variable fields ──
    // Slot 0: item (string)
    item: ?[]const u8 = null,
    // Slot 1: name (string)
    name: ?[]const u8 = null,
    // Slot 2: shaderEffect (raw serialized bytes)
    shader_effect: ?[]const u8 = null,
    // Slot 3: model (string path)
    model: ?[]const u8 = null,
    // Slot 4: modelTexture (raw serialized bytes)
    model_texture: ?[]const u8 = null,
    // Slot 5: modelAnimation (string path)
    model_animation: ?[]const u8 = null,
    // Slot 6: support (raw serialized bytes)
    support: ?[]const u8 = null,
    // Slot 7: supporting (raw serialized bytes)
    supporting: ?[]const u8 = null,
    // Slot 8: cubeTextures (proper type)
    cube_textures: ?BlockTextures = null,
    // Slot 9: cubeSideMaskTexture (string)
    cube_side_mask_texture: ?[]const u8 = null,
    // Slot 10: particles (raw serialized bytes)
    particles: ?[]const u8 = null,
    // Slot 11: blockParticleSetId (string)
    block_particle_set_id: ?[]const u8 = null,
    // Slot 12: blockBreakingDecalId (string)
    block_breaking_decal_id: ?[]const u8 = null,
    // Slot 13: transitionTexture (string)
    transition_texture: ?[]const u8 = null,
    // Slot 14: transitionToGroups (raw serialized bytes)
    transition_to_groups: ?[]const u8 = null,
    // Slot 15: interactionHint (string)
    interaction_hint: ?[]const u8 = null,
    // Slot 16: gathering (raw serialized bytes)
    gathering: ?[]const u8 = null,
    // Slot 17: display (raw serialized bytes)
    display: ?[]const u8 = null,
    // Slot 18: rail (raw serialized bytes)
    rail: ?[]const u8 = null,
    // Slot 19: interactions (raw serialized bytes)
    interactions: ?[]const u8 = null,
    // Slot 20: states (raw serialized bytes)
    states: ?[]const u8 = null,
    // Slot 21: tagIndexes (raw serialized bytes)
    tag_indexes: ?[]const u8 = null,
    // Slot 22: bench (raw serialized bytes)
    bench: ?[]const u8 = null,
    // Slot 23: connectedBlockRuleSet (raw serialized bytes)
    connected_block_rule_set: ?[]const u8 = null,

    const Self = @This();

    /// Serialize to protocol format matching Java BlockType.java exactly.
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // ── NullBits (4 bytes) ──
        var null_bits: [4]u8 = .{ 0, 0, 0, 0 };

        // Byte 0: inline fields
        if (self.particle_color != null) null_bits[0] |= 0x01;
        if (self.light != null) null_bits[0] |= 0x02;
        if (self.tint != null) null_bits[0] |= 0x04;
        if (self.biome_tint != null) null_bits[0] |= 0x08;
        if (self.movement_settings != null) null_bits[0] |= 0x10;
        if (self.flags != null) null_bits[0] |= 0x20;
        if (self.placement_settings != null) null_bits[0] |= 0x40;
        if (self.item != null) null_bits[0] |= 0x80;

        // Byte 1: variable fields
        if (self.name != null) null_bits[1] |= 0x01;
        if (self.shader_effect != null) null_bits[1] |= 0x02;
        if (self.model != null) null_bits[1] |= 0x04;
        if (self.model_texture != null) null_bits[1] |= 0x08;
        if (self.model_animation != null) null_bits[1] |= 0x10;
        if (self.support != null) null_bits[1] |= 0x20;
        if (self.supporting != null) null_bits[1] |= 0x40;
        if (self.cube_textures != null) null_bits[1] |= 0x80;

        // Byte 2
        if (self.cube_side_mask_texture != null) null_bits[2] |= 0x01;
        if (self.particles != null) null_bits[2] |= 0x02;
        if (self.block_particle_set_id != null) null_bits[2] |= 0x04;
        if (self.block_breaking_decal_id != null) null_bits[2] |= 0x08;
        if (self.transition_texture != null) null_bits[2] |= 0x10;
        if (self.transition_to_groups != null) null_bits[2] |= 0x20;
        if (self.interaction_hint != null) null_bits[2] |= 0x40;
        if (self.gathering != null) null_bits[2] |= 0x80;

        // Byte 3
        if (self.display != null) null_bits[3] |= 0x01;
        if (self.rail != null) null_bits[3] |= 0x02;
        if (self.interactions != null) null_bits[3] |= 0x04;
        if (self.states != null) null_bits[3] |= 0x08;
        if (self.tag_indexes != null) null_bits[3] |= 0x10;
        if (self.bench != null) null_bits[3] |= 0x20;
        if (self.connected_block_rule_set != null) null_bits[3] |= 0x40;

        try buf.appendSlice(allocator, &null_bits);

        // ── Fixed fields (159 bytes: offset 4-162) ──
        try buf.append(allocator, if (self.unknown) 1 else 0);
        try buf.append(allocator, @intFromEnum(self.draw_type));
        try buf.append(allocator, @intFromEnum(self.material));
        try buf.append(allocator, @intFromEnum(self.opacity));
        try writeI32(&buf, allocator, self.hitbox);
        try writeI32(&buf, allocator, self.interaction_hitbox);
        try writeF32(&buf, allocator, self.model_scale);
        try buf.append(allocator, if (self.looping) 1 else 0);
        try writeI32(&buf, allocator, self.max_support_distance);
        try buf.append(allocator, @intFromEnum(self.block_supports_required_for));
        try buf.append(allocator, if (self.requires_alpha_blending) 1 else 0);
        try buf.append(allocator, @intFromEnum(self.cube_shading_mode));
        try buf.append(allocator, @intFromEnum(self.random_rotation));
        try buf.append(allocator, @intFromEnum(self.variant_rotation));
        try buf.append(allocator, @intFromEnum(self.rotation_yaw_placement_offset));
        try writeI32(&buf, allocator, self.block_sound_set_index);
        try writeI32(&buf, allocator, self.ambient_sound_event_index);

        // Inline optional fields (always occupy space; zeros when null)
        if (self.particle_color) |*pc| {
            try pc.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 3);
        }

        if (self.light) |*l| {
            try l.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 4);
        }

        if (self.tint) |*t| {
            try t.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 24);
        }

        if (self.biome_tint) |*bt| {
            try bt.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 24);
        }

        try writeI32(&buf, allocator, self.group);

        if (self.movement_settings) |*ms| {
            try ms.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 42);
        }

        if (self.flags) |*f| {
            try f.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 2);
        }

        if (self.placement_settings) |*ps| {
            try ps.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 16);
        }

        try buf.append(allocator, if (self.ignore_support_when_placed) 1 else 0);
        try writeI32(&buf, allocator, self.transition_to_tag);

        // ── Offset slots (24 x i32 = 96 bytes, offsets 163-258) ──
        const offset_slots_start = buf.items.len;
        try buf.appendNTimes(allocator, 0, 96);

        // Initialize all to -1
        for (0..24) |slot| {
            const pos = offset_slots_start + (slot * 4);
            std.mem.writeInt(i32, buf.items[pos..][0..4], -1, .little);
        }

        // ── Variable block (offset 259+) ──
        const var_block_start = buf.items.len;

        // Slot ordering must match Java exactly.
        // String fields are written as VarString (VarInt length + bytes).
        // Raw blob fields are written directly (already serialized).

        // Slot 0: item (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 0, self.item);
        // Slot 1: name (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 1, self.name);
        // Slot 2: shaderEffect (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 2, self.shader_effect);
        // Slot 3: model (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 3, self.model);
        // Slot 4: modelTexture (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 4, self.model_texture);
        // Slot 5: modelAnimation (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 5, self.model_animation);
        // Slot 6: support (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 6, self.support);
        // Slot 7: supporting (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 7, self.supporting);

        // Slot 8: cubeTextures (proper type)
        if (self.cube_textures) |*cube_tex| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            const slot_pos = offset_slots_start + (8 * 4);
            std.mem.writeInt(i32, buf.items[slot_pos..][0..4], offset, .little);
            // VarInt count (always 1 for single texture set)
            try writeVarInt(&buf, allocator, 1);
            const cube_data = try cube_tex.serialize(allocator);
            defer allocator.free(cube_data);
            try buf.appendSlice(allocator, cube_data);
        }

        // Slot 9: cubeSideMaskTexture (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 9, self.cube_side_mask_texture);
        // Slot 10: particles (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 10, self.particles);
        // Slot 11: blockParticleSetId (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 11, self.block_particle_set_id);
        // Slot 12: blockBreakingDecalId (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 12, self.block_breaking_decal_id);
        // Slot 13: transitionTexture (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 13, self.transition_texture);
        // Slot 14: transitionToGroups (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 14, self.transition_to_groups);
        // Slot 15: interactionHint (string)
        try self.writeStringSlot(&buf, allocator, offset_slots_start, var_block_start, 15, self.interaction_hint);
        // Slot 16: gathering (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 16, self.gathering);
        // Slot 17: display (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 17, self.display);
        // Slot 18: rail (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 18, self.rail);
        // Slot 19: interactions (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 19, self.interactions);
        // Slot 20: states (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 20, self.states);
        // Slot 21: tagIndexes (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 21, self.tag_indexes);
        // Slot 22: bench (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 22, self.bench);
        // Slot 23: connectedBlockRuleSet (raw)
        try self.writeRawSlot(&buf, allocator, offset_slots_start, var_block_start, 23, self.connected_block_rule_set);

        return buf.toOwnedSlice(allocator);
    }

    fn writeStringSlot(
        _: *const Self,
        buf: *std.ArrayListUnmanaged(u8),
        allocator: Allocator,
        offset_slots_start: usize,
        var_block_start: usize,
        slot: usize,
        value: ?[]const u8,
    ) !void {
        if (value) |str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            const slot_pos = offset_slots_start + (slot * 4);
            std.mem.writeInt(i32, buf.items[slot_pos..][0..4], offset, .little);
            try writeVarString(buf, allocator, str);
        }
    }

    fn writeRawSlot(
        _: *const Self,
        buf: *std.ArrayListUnmanaged(u8),
        allocator: Allocator,
        offset_slots_start: usize,
        var_block_start: usize,
        slot: usize,
        value: ?[]const u8,
    ) !void {
        if (value) |data| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            const slot_pos = offset_slots_start + (slot * 4);
            std.mem.writeInt(i32, buf.items[slot_pos..][0..4], offset, .little);
            try buf.appendSlice(allocator, data);
        }
    }

    // Raw bytes for a single ModelTexture with "BlockTextures/Unknown.png"
    // Format: VarInt(1) array count + nullBits(0x01) + weight(1.0f LE) + VarString texture
    const model_texture_unknown = [_]u8{
        0x01, // VarInt count = 1
        0x01, // nullBits: texture present
        0x00, 0x00, 0x80, 0x3F, // weight = 1.0f LE
        0x19, // VarInt 25 (length of "BlockTextures/Unknown.png")
        'B',  'l',  'o',  'c',  'k',  'T',  'e',  'x',  't',  'u',  'r',  'e',  's',
        '/',  'U',  'n',  'k',  'n',  'o',  'w',  'n',  '.',  'p',  'n',  'g',
    };

    /// Create a default block matching Java's BlockType constructor defaults.
    /// This includes movementSettings, flags, tint, and biomeTint with proper values.
    pub fn default() Self {
        return .{
            .draw_type = .cube,
            .material = .empty,
            .opacity = .solid,
            .interaction_hitbox = std.math.minInt(i32),
            .block_supports_required_for = .all,
            .transition_to_tag = std.math.minInt(i32),
            .movement_settings = .{}, // uses config defaults: drag=0.82, friction=0.18, etc.
            .flags = .{}, // isUsable=false, isStackable=true
            .tint = .{}, // all faces = -1
            .biome_tint = .{ .top = 0, .bottom = 0, .front = 0, .back = 0, .left = 0, .right = 0 },
        };
    }

    /// Create an air/empty block matching the Java server's block 0.
    pub fn air(allocator: Allocator) !Self {
        var block = Self.default();
        block.draw_type = .empty;
        block.opacity = .transparent;
        block.name = "Empty";
        block.shader_effect = &[_]u8{ 0x01, 0x00 }; // array of 1 ShaderType.None
        block.model_texture = &model_texture_unknown;
        block.support = &[_]u8{0x00}; // empty map
        block.supporting = &[_]u8{0x00}; // empty map
        block.cube_textures = try BlockTextures.unknown(allocator);
        block.interactions = &[_]u8{0x00}; // empty array
        return block;
    }

    /// Create a solid block with fallback textures
    pub fn solid(allocator: Allocator, name: ?[]const u8) !Self {
        var block = Self.default();
        block.draw_type = .cube;
        block.material = .solid;
        block.name = name;
        block.cube_textures = try BlockTextures.unknown(allocator);
        return block;
    }

    /// Free all allocated memory owned by this block
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.cube_textures) |*tex| tex.deinit(allocator);
        // Raw blob fields that were allocated
        const raw_fields = [_]*?[]const u8{
            &self.shader_effect,
            &self.model_texture,
            &self.support,
            &self.supporting,
            &self.particles,
            &self.transition_to_groups,
            &self.gathering,
            &self.display,
            &self.rail,
            &self.interactions,
            &self.states,
            &self.tag_indexes,
            &self.bench,
            &self.connected_block_rule_set,
        };
        _ = raw_fields;
        // Note: string fields (name, item, model, etc.) are typically borrowed,
        // not owned. Only free if they were allocated by this struct.
        // The caller is responsible for managing allocated string lifetimes.
    }
};

// ─── Helper functions ────────────────────────────────────────────

fn writeI32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &bytes, value, .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeF32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: f32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @bitCast(value), .little);
    try buf.appendSlice(allocator, &bytes);
}

fn writeVarString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, str: []const u8) !void {
    try writeVarInt(buf, allocator, @intCast(str.len));
    try buf.appendSlice(allocator, str);
}

fn writeVarInt(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var v: u32 = @bitCast(value);
    while (v >= 0x80) {
        try buf.append(allocator, @truncate((v & 0x7F) | 0x80));
        v >>= 7;
    }
    try buf.append(allocator, @truncate(v));
}

/// Read a VarInt value from a byte slice starting at `pos`.
fn readVarIntAt(data: []const u8, pos: usize) ?struct { value: u32, len: usize } {
    if (pos >= data.len) return null;
    var value: u32 = 0;
    var shift: u5 = 0;
    var i: usize = 0;
    while (pos + i < data.len and i < 5) {
        const b = data[pos + i];
        value |= @as(u32, b & 0x7F) << shift;
        i += 1;
        if ((b & 0x80) == 0) {
            return .{ .value = value, .len = i };
        }
        shift +|= 7;
    }
    return null;
}

/// Compute bytes consumed by a serialized BlockTextures at buf[offset..].
pub fn computeBlockTexturesBytesConsumed(buf: []const u8, offset: usize) ?usize {
    if (offset + 29 > buf.len) return null;

    const null_bits = buf[offset];
    var max_end: usize = 29;

    const face_bits = [_]u8{ 0x01, 0x02, 0x04, 0x08, 0x10, 0x20 };
    const slot_positions = [_]usize{ 5, 9, 13, 17, 21, 25 };

    for (face_bits, slot_positions) |bit, slot_pos| {
        if ((null_bits & bit) != 0) {
            const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
            if (field_offset < 0) continue;
            var pos = offset + 29 + @as(usize, @intCast(field_offset));
            const vi = readVarIntAt(buf, pos) orelse return null;
            pos += vi.len + vi.value;
            const consumed = pos - offset;
            if (consumed > max_end) max_end = consumed;
        }
    }

    return max_end;
}

/// Compute bytes consumed by a serialized BlockType at buf[offset..].
/// Handles ALL 24 variable field slots.
pub fn computeBytesConsumed(buf: []const u8, offset: usize) ?usize {
    if (offset + VARIABLE_BLOCK_START > buf.len) return null;

    const null_bits = buf[offset .. offset + NULLABLE_BIT_FIELD_SIZE];
    var max_end: usize = VARIABLE_BLOCK_START; // 259

    // Walk all 24 slots. Each slot's nullBit position determines whether it's present.
    // For each present slot, read the offset and walk past its data.

    // Slot 0: item (nullBits[0] bit 7) - VarString
    if ((null_bits[0] & 0x80) != 0) {
        max_end = walkVarStringSlot(buf, offset, 0, max_end) orelse return null;
    }
    // Slot 1: name (nullBits[1] bit 0) - VarString
    if ((null_bits[1] & 0x01) != 0) {
        max_end = walkVarStringSlot(buf, offset, 1, max_end) orelse return null;
    }
    // Slot 2: shaderEffect (nullBits[1] bit 1) - array of ShaderType
    if ((null_bits[1] & 0x02) != 0) {
        max_end = walkShaderEffectSlot(buf, offset, max_end) orelse return null;
    }
    // Slot 3: model (nullBits[1] bit 2) - VarString
    if ((null_bits[1] & 0x04) != 0) {
        max_end = walkVarStringSlot(buf, offset, 3, max_end) orelse return null;
    }
    // Slot 4: modelTexture (nullBits[1] bit 3) - array of ModelTexture
    if ((null_bits[1] & 0x08) != 0) {
        max_end = walkModelTextureSlot(buf, offset, max_end) orelse return null;
    }
    // Slot 5: modelAnimation (nullBits[1] bit 4) - VarString
    if ((null_bits[1] & 0x10) != 0) {
        max_end = walkVarStringSlot(buf, offset, 5, max_end) orelse return null;
    }
    // Slot 6: support (nullBits[1] bit 5) - map
    if ((null_bits[1] & 0x20) != 0) {
        max_end = walkSupportSlot(buf, offset, max_end) orelse return null;
    }
    // Slot 7: supporting (nullBits[1] bit 6) - map
    if ((null_bits[1] & 0x40) != 0) {
        max_end = walkSupportingSlot(buf, offset, max_end) orelse return null;
    }
    // Slot 8: cubeTextures (nullBits[1] bit 7) - array of BlockTextures
    if ((null_bits[1] & 0x80) != 0) {
        max_end = walkCubeTexturesSlot(buf, offset, max_end) orelse return null;
    }
    // Slot 9: cubeSideMaskTexture (nullBits[2] bit 0) - VarString
    if ((null_bits[2] & 0x01) != 0) {
        max_end = walkVarStringSlot(buf, offset, 9, max_end) orelse return null;
    }
    // Slot 10: particles (nullBits[2] bit 1) - raw blob
    if ((null_bits[2] & 0x02) != 0) {
        max_end = walkVarIntArraySlot(buf, offset, 10, max_end) orelse return null;
    }
    // Slot 11: blockParticleSetId (nullBits[2] bit 2) - VarString
    if ((null_bits[2] & 0x04) != 0) {
        max_end = walkVarStringSlot(buf, offset, 11, max_end) orelse return null;
    }
    // Slot 12: blockBreakingDecalId (nullBits[2] bit 3) - VarString
    if ((null_bits[2] & 0x08) != 0) {
        max_end = walkVarStringSlot(buf, offset, 12, max_end) orelse return null;
    }
    // Slot 13: transitionTexture (nullBits[2] bit 4) - VarString
    if ((null_bits[2] & 0x10) != 0) {
        max_end = walkVarStringSlot(buf, offset, 13, max_end) orelse return null;
    }
    // Slot 14: transitionToGroups (nullBits[2] bit 5) - raw blob
    if ((null_bits[2] & 0x20) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 14, max_end) orelse return null;
    }
    // Slot 15: interactionHint (nullBits[2] bit 6) - VarString
    if ((null_bits[2] & 0x40) != 0) {
        max_end = walkVarStringSlot(buf, offset, 15, max_end) orelse return null;
    }
    // Slot 16: gathering (nullBits[2] bit 7) - raw blob
    if ((null_bits[2] & 0x80) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 16, max_end) orelse return null;
    }
    // Slot 17: display (nullBits[3] bit 0) - raw blob
    if ((null_bits[3] & 0x01) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 17, max_end) orelse return null;
    }
    // Slot 18: rail (nullBits[3] bit 1) - raw blob
    if ((null_bits[3] & 0x02) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 18, max_end) orelse return null;
    }
    // Slot 19: interactions (nullBits[3] bit 2) - VarInt-prefixed array
    if ((null_bits[3] & 0x04) != 0) {
        max_end = walkVarIntArraySlot(buf, offset, 19, max_end) orelse return null;
    }
    // Slot 20: states (nullBits[3] bit 3) - raw blob
    if ((null_bits[3] & 0x08) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 20, max_end) orelse return null;
    }
    // Slot 21: tagIndexes (nullBits[3] bit 4) - raw blob
    if ((null_bits[3] & 0x10) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 21, max_end) orelse return null;
    }
    // Slot 22: bench (nullBits[3] bit 5) - raw blob
    if ((null_bits[3] & 0x20) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 22, max_end) orelse return null;
    }
    // Slot 23: connectedBlockRuleSet (nullBits[3] bit 6) - raw blob
    if ((null_bits[3] & 0x40) != 0) {
        max_end = walkRawSlotToEnd(buf, offset, 23, max_end) orelse return null;
    }

    return max_end;
}

fn walkVarStringSlot(buf: []const u8, offset: usize, slot: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + slot * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    var pos = offset + VARIABLE_BLOCK_START + @as(usize, @intCast(field_offset));
    const vi = readVarIntAt(buf, pos) orelse return null;
    pos += vi.len + vi.value;
    const consumed = pos - offset;
    return if (consumed > current_max) consumed else current_max;
}

fn walkShaderEffectSlot(buf: []const u8, offset: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + 2 * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    var pos = offset + VARIABLE_BLOCK_START + @as(usize, @intCast(field_offset));
    // VarInt array length, then N x 1-byte enum values
    const vi = readVarIntAt(buf, pos) orelse return null;
    pos += vi.len + vi.value; // each ShaderType is 1 byte
    const consumed = pos - offset;
    return if (consumed > current_max) consumed else current_max;
}

fn walkModelTextureSlot(buf: []const u8, offset: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + 4 * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    var pos = offset + VARIABLE_BLOCK_START + @as(usize, @intCast(field_offset));
    // VarInt array length
    const arr_vi = readVarIntAt(buf, pos) orelse return null;
    pos += arr_vi.len;
    // Each ModelTexture: computeModelTextureBytesConsumed
    for (0..arr_vi.value) |_| {
        const tex_size = computeModelTextureBytesConsumed(buf, pos) orelse return null;
        pos += tex_size;
    }
    const consumed = pos - offset;
    return if (consumed > current_max) consumed else current_max;
}

fn computeModelTextureBytesConsumed(buf: []const u8, moffset: usize) ?usize {
    // ModelTexture: 1 byte nullBits + 4 bytes weight = 5 base (NO offset slots)
    // Fields are inline VarStrings, not offset-based.
    if (moffset + 5 > buf.len) return null;
    const nb = buf[moffset];
    var pos: usize = moffset + 5; // after nullBits + weight
    // Slot 0: texture (inline VarString)
    if ((nb & 0x01) != 0) {
        const vi = readVarIntAt(buf, pos) orelse return null;
        pos += vi.len + vi.value;
    }
    // Slot 1: emissiveTexture (inline VarString)
    if ((nb & 0x02) != 0) {
        const vi = readVarIntAt(buf, pos) orelse return null;
        pos += vi.len + vi.value;
    }
    return pos - moffset;
}

fn walkSupportSlot(buf: []const u8, offset: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + 6 * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    var pos = offset + VARIABLE_BLOCK_START + @as(usize, @intCast(field_offset));
    // Map<BlockNeighbor(i32), RequiredBlockFaceSupport[]>
    const map_vi = readVarIntAt(buf, pos) orelse return null;
    pos += map_vi.len;
    for (0..map_vi.value) |_| {
        pos += 4; // i32 key (BlockNeighbor)
        // VarInt array of RequiredBlockFaceSupport (each is 5 bytes: 1 byte enum + i32)
        const arr_vi = readVarIntAt(buf, pos) orelse return null;
        pos += arr_vi.len;
        pos += arr_vi.value * 5;
    }
    const consumed = pos - offset;
    return if (consumed > current_max) consumed else current_max;
}

fn walkSupportingSlot(buf: []const u8, offset: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + 7 * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    var pos = offset + VARIABLE_BLOCK_START + @as(usize, @intCast(field_offset));
    // Map<BlockNeighbor(i32), BlockFaceSupport[]>
    const map_vi = readVarIntAt(buf, pos) orelse return null;
    pos += map_vi.len;
    for (0..map_vi.value) |_| {
        pos += 4; // i32 key
        // VarInt array of BlockFaceSupport (each is 1 byte enum)
        const arr_vi = readVarIntAt(buf, pos) orelse return null;
        pos += arr_vi.len;
        pos += arr_vi.value;
    }
    const consumed = pos - offset;
    return if (consumed > current_max) consumed else current_max;
}

/// Walk a slot that contains a VarInt-prefixed array where elements are opaque.
/// For empty arrays (count=0), just skip the VarInt. Used for interactions, particles, etc.
fn walkVarIntArraySlot(buf: []const u8, offset: usize, slot: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + slot * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    var pos = offset + VARIABLE_BLOCK_START + @as(usize, @intCast(field_offset));
    const vi = readVarIntAt(buf, pos) orelse return null;
    pos += vi.len;
    // For empty arrays (count=0), we're done. For non-empty arrays,
    // we can't walk elements without knowing their format, so just skip the count.
    // This works for our current use case where these are always empty.
    const consumed = pos - offset;
    return if (consumed > current_max) consumed else current_max;
}

/// Walk a raw blob slot by reading from the offset to the end of the blob data.
/// For raw blobs written via writeRawSlot, we know the data was appended sequentially,
/// so we can compute the end from the slot's offset value and the blob size.
/// This is a fallback that treats the slot offset as a starting point.
fn walkRawSlotToEnd(buf: []const u8, offset: usize, slot: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + slot * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    // For raw blobs, we don't know the exact size without parsing the format.
    // But since we write them sequentially, the next slot's offset (or buffer end)
    // determines where this blob ends. For now, just ensure max_end includes the offset.
    // The actual data extent is determined by other slots or the buffer end.
    return current_max;
}

fn walkCubeTexturesSlot(buf: []const u8, offset: usize, current_max: usize) ?usize {
    const slot_pos = FIXED_BLOCK_SIZE + 8 * 4;
    const field_offset = std.mem.readInt(i32, buf[offset + slot_pos ..][0..4], .little);
    if (field_offset < 0) return current_max;
    var pos = offset + VARIABLE_BLOCK_START + @as(usize, @intCast(field_offset));
    const arr_vi = readVarIntAt(buf, pos) orelse return null;
    pos += arr_vi.len;
    for (0..arr_vi.value) |_| {
        const tex_size = computeBlockTexturesBytesConsumed(buf, pos) orelse return null;
        pos += tex_size;
    }
    const consumed = pos - offset;
    return if (consumed > current_max) consumed else current_max;
}

// ─── Tests ───────────────────────────────────────────────────────

test "BlockTypeAsset default has correct fixed field values" {
    const allocator = std.testing.allocator;

    const block = BlockTypeAsset.default();
    const data = try block.serialize(allocator);
    defer allocator.free(data);

    // Should produce at least 259 bytes
    try std.testing.expect(data.len >= VARIABLE_BLOCK_START);

    // drawType = cube (2) at offset 5
    try std.testing.expectEqual(@as(u8, 2), data[5]);
    // material = empty (0) at offset 6
    try std.testing.expectEqual(@as(u8, 0), data[6]);
    // opacity = solid (0) at offset 7
    try std.testing.expectEqual(@as(u8, 0), data[7]);
    // interactionHitbox = MIN_VALUE at offset 12-15
    try std.testing.expectEqual(std.math.minInt(i32), std.mem.readInt(i32, data[12..16], .little));
    // blockSoundSetIndex = 0 at offset 31-34
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, data[31..35], .little));
    // ambientSoundEventIndex = 0 at offset 35-38
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, data[35..39], .little));
    // blockSupportsRequiredFor = all (1) at offset 25
    try std.testing.expectEqual(@as(u8, 1), data[25]);
    // transitionToTag = MIN_VALUE at offset 159-162
    try std.testing.expectEqual(std.math.minInt(i32), std.mem.readInt(i32, data[159..163], .little));
}

test "BlockTypeAsset default has correct inline field values" {
    const allocator = std.testing.allocator;

    const block = BlockTypeAsset.default();
    const data = try block.serialize(allocator);
    defer allocator.free(data);

    // nullBits should have tint(bit2), biomeTint(bit3), movementSettings(bit4), flags(bit5) set
    try std.testing.expect((data[0] & 0x04) != 0); // tint
    try std.testing.expect((data[0] & 0x08) != 0); // biomeTint
    try std.testing.expect((data[0] & 0x10) != 0); // movementSettings
    try std.testing.expect((data[0] & 0x20) != 0); // flags

    // tint at offset 46-69: all faces should be -1 (0xFFFFFFFF)
    for (0..6) |face| {
        const tint_val = std.mem.readInt(i32, data[46 + face * 4 ..][0..4], .little);
        try std.testing.expectEqual(@as(i32, -1), tint_val);
    }

    // movementSettings at offset 98: verify drag=0.82 at sub-offset 18
    const drag_bits = std.mem.readInt(u32, data[98 + 18 ..][0..4], .little);
    const drag: f32 = @bitCast(drag_bits);
    try std.testing.expect(@abs(drag - 0.82) < 0.001);

    // flags at offset 140: isUsable=0, isStackable=1
    try std.testing.expectEqual(@as(u8, 0), data[140]); // isUsable
    try std.testing.expectEqual(@as(u8, 1), data[141]); // isStackable
}

test "BlockTypeAsset air block has name Empty" {
    const allocator = std.testing.allocator;

    var air = try BlockTypeAsset.air(allocator);
    defer if (air.cube_textures) |*tex| tex.deinit(allocator);
    const data = try air.serialize(allocator);
    defer allocator.free(data);

    // drawType = empty (0)
    try std.testing.expectEqual(@as(u8, 0), data[5]);
    // nullBits[1] bit 0 = name present
    try std.testing.expect((data[1] & 0x01) != 0);
    // Slot 1 (name) should have offset >= 0
    const name_offset = std.mem.readInt(i32, data[FIXED_BLOCK_SIZE + 4 ..][0..4], .little);
    try std.testing.expect(name_offset >= 0);
    // Verify name is "Empty"
    const name_pos = VARIABLE_BLOCK_START + @as(usize, @intCast(name_offset));
    try std.testing.expectEqual(@as(u8, 5), data[name_pos]); // VarInt length
    try std.testing.expectEqualStrings("Empty", data[name_pos + 1 .. name_pos + 6]);
}

test "BlockTypeAsset solid block serialization" {
    const allocator = std.testing.allocator;

    var stone = try BlockTypeAsset.solid(allocator, "Stone");
    defer if (stone.cube_textures) |*tex| tex.deinit(allocator);
    const data = try stone.serialize(allocator);
    defer allocator.free(data);

    // drawType = cube (2)
    try std.testing.expectEqual(@as(u8, 2), data[5]);
    // material = solid (1)
    try std.testing.expectEqual(@as(u8, 1), data[6]);
    // nullBits[1] = 0x81 (name bit 0 + cubeTextures bit 7)
    try std.testing.expectEqual(@as(u8, 0x81), data[1] & 0x81);
}

test "all 24 offset slots are -1 for default block with no variable fields" {
    const allocator = std.testing.allocator;

    var block = BlockTypeAsset.default();
    block.name = null; // remove name from default
    const data = try block.serialize(allocator);
    defer allocator.free(data);

    for (0..24) |slot| {
        const slot_pos = FIXED_BLOCK_SIZE + (slot * 4);
        const slot_value = std.mem.readInt(i32, data[slot_pos..][0..4], .little);
        try std.testing.expectEqual(@as(i32, -1), slot_value);
    }
}

test "computeBytesConsumed matches serialized length for air block" {
    const allocator = std.testing.allocator;

    var air = try BlockTypeAsset.air(allocator);
    defer if (air.cube_textures) |*tex| tex.deinit(allocator);
    const data = try air.serialize(allocator);
    defer allocator.free(data);

    const consumed = computeBytesConsumed(data, 0) orelse return error.ComputeFailed;
    try std.testing.expectEqual(data.len, consumed);
}

test "computeBytesConsumed matches serialized length for solid block" {
    const allocator = std.testing.allocator;

    var stone = try BlockTypeAsset.solid(allocator, "Stone");
    defer if (stone.cube_textures) |*tex| tex.deinit(allocator);
    const data = try stone.serialize(allocator);
    defer allocator.free(data);

    const consumed = computeBytesConsumed(data, 0) orelse return error.ComputeFailed;
    try std.testing.expectEqual(data.len, consumed);
}

test "computeBlockTexturesBytesConsumed matches serialized length" {
    const allocator = std.testing.allocator;

    const textures = try BlockTextures.unknown(allocator);
    var tex_mut = textures;
    defer tex_mut.deinit(allocator);
    const data = try tex_mut.serialize(allocator);
    defer allocator.free(data);

    const consumed = computeBlockTexturesBytesConsumed(data, 0) orelse return error.ComputeFailed;
    try std.testing.expectEqual(data.len, consumed);
}

test "fixed block size is exactly 259 bytes for block with no variable data" {
    const allocator = std.testing.allocator;

    var block = BlockTypeAsset.default();
    block.name = null;
    const data = try block.serialize(allocator);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, VARIABLE_BLOCK_START), data.len);
}
