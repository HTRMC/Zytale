/// Block Type Asset
///
/// Represents a block type definition for the protocol.
/// Based on com/hypixel/hytale/protocol/BlockType.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Draw type for blocks
/// Values must match com/hypixel/hytale/protocol/DrawType.java
pub const DrawType = enum(u8) {
    empty = 0,
    gizmo_cube = 1,
    cube = 2,
    model = 3,
    cube_with_model = 4,

    pub fn fromValue(value: u8) DrawType {
        return @enumFromInt(value);
    }
};

// Compile-time verification that DrawType values match Java protocol
comptime {
    std.debug.assert(@intFromEnum(DrawType.empty) == 0);
    std.debug.assert(@intFromEnum(DrawType.gizmo_cube) == 1);
    std.debug.assert(@intFromEnum(DrawType.cube) == 2);
    std.debug.assert(@intFromEnum(DrawType.model) == 3);
    std.debug.assert(@intFromEnum(DrawType.cube_with_model) == 4);
}

/// Block material type
pub const BlockMaterial = enum(u8) {
    empty = 0,
    solid = 1,
    // Add more as needed

    pub fn fromValue(value: u8) BlockMaterial {
        return @enumFromInt(value);
    }
};

/// Block opacity
pub const Opacity = enum(u8) {
    solid = 0,
    transparent = 1,
    // Add more as needed

    pub fn fromValue(value: u8) Opacity {
        return @enumFromInt(value);
    }
};

/// Shading mode for cube blocks
pub const ShadingMode = enum(u8) {
    standard = 0,
    // Add more as needed
};

/// Random rotation options
pub const RandomRotation = enum(u8) {
    none = 0,
    // Add more as needed
};

/// Variant rotation options
pub const VariantRotation = enum(u8) {
    none = 0,
    // Add more as needed
};

/// Rotation options
pub const Rotation = enum(u8) {
    none = 0,
    // Add more as needed
};

/// Block supports required for type
pub const BlockSupportsRequiredForType = enum(u8) {
    any = 0,
    // Add more as needed
};

/// Cube textures - 6 face textures for a cube block
/// Format: Array of texture definitions with 6 faces (top, bottom, front, back, left, right)
pub const BlockTextures = struct {
    /// Texture paths for each face (nullable to match Java @Nullable String)
    top: ?[]const u8 = null,
    bottom: ?[]const u8 = null,
    front: ?[]const u8 = null,
    back: ?[]const u8 = null,
    left: ?[]const u8 = null,
    right: ?[]const u8 = null,
    /// Weight for this texture set (f32)
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
    /// Format matches BlockTextures.java serialize() (lines 213-297):
    /// [1 byte] nullBits (bits 0-5 for top, bottom, front, back, left, right)
    /// [4 bytes] weight (f32 LE)
    /// [24 bytes] 6 offset slots (4 bytes each)
    /// Variable block starting at offset 29 with VarStrings for each face
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Calculate nullBits for the 6 faces
        var null_bits: u8 = 0;
        if (self.top != null) null_bits |= 0x01; // bit 0
        if (self.bottom != null) null_bits |= 0x02; // bit 1
        if (self.front != null) null_bits |= 0x04; // bit 2
        if (self.back != null) null_bits |= 0x08; // bit 3
        if (self.left != null) null_bits |= 0x10; // bit 4
        if (self.right != null) null_bits |= 0x20; // bit 5

        // Write nullBits (1 byte)
        try buf.append(allocator, null_bits);

        // Write weight (f32 LE)
        try writeF32(&buf, allocator, self.weight);

        // Write 6 offset slots (24 bytes total)
        const top_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const bottom_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const front_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const back_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const left_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const right_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        // Variable block start position (offset 29)
        const var_block_start = buf.items.len;

        // Write variable fields
        if (self.top) |top_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[top_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, top_str);
        } else {
            std.mem.writeInt(i32, buf.items[top_offset_pos..][0..4], -1, .little);
        }

        if (self.bottom) |bottom_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[bottom_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, bottom_str);
        } else {
            std.mem.writeInt(i32, buf.items[bottom_offset_pos..][0..4], -1, .little);
        }

        if (self.front) |front_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[front_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, front_str);
        } else {
            std.mem.writeInt(i32, buf.items[front_offset_pos..][0..4], -1, .little);
        }

        if (self.back) |back_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[back_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, back_str);
        } else {
            std.mem.writeInt(i32, buf.items[back_offset_pos..][0..4], -1, .little);
        }

        if (self.left) |left_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[left_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, left_str);
        } else {
            std.mem.writeInt(i32, buf.items[left_offset_pos..][0..4], -1, .little);
        }

        if (self.right) |right_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[right_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, right_str);
        } else {
            std.mem.writeInt(i32, buf.items[right_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated texture paths
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.top) |s| allocator.free(s);
        if (self.bottom) |s| allocator.free(s);
        if (self.front) |s| allocator.free(s);
        if (self.back) |s| allocator.free(s);
        if (self.left) |s| allocator.free(s);
        if (self.right) |s| allocator.free(s);
    }
};

/// Block type asset
pub const BlockTypeAsset = struct {
    // Optional fields (null = not present in nullBits)
    item: ?[]const u8 = null,
    name: ?[]const u8 = null,
    cube_textures: ?BlockTextures = null,

    // Required fields with defaults
    unknown: bool = false,
    draw_type: DrawType = .empty,
    material: BlockMaterial = .empty,
    opacity: Opacity = .solid,

    hitbox: i32 = 0,
    interaction_hitbox: i32 = 0,
    model_scale: f32 = 1.0,
    looping: bool = false,
    max_support_distance: i32 = 0,
    block_supports_required_for: BlockSupportsRequiredForType = .any,
    requires_alpha_blending: bool = false,
    cube_shading_mode: ShadingMode = .standard,
    random_rotation: RandomRotation = .none,
    variant_rotation: VariantRotation = .none,
    rotation_yaw_placement_offset: Rotation = .none,
    block_sound_set_index: i32 = -1,
    ambient_sound_event_index: i32 = -1,
    group: i32 = 0,
    ignore_support_when_placed: bool = false,
    transition_to_tag: i32 = 0,

    const Self = @This();

    /// Serialize to protocol format
    /// Returns the serialized bytes
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        // Validation: Empty blocks (air) MUST NOT have a name
        // The client validates: if drawType == empty && name != null, it throws
        // "Block type with EmptyBlockId but has name"
        if (self.draw_type == .empty and self.name != null) {
            return error.EmptyBlockCannotHaveName;
        }

        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Calculate nullBits
        var null_bits: [4]u8 = .{ 0, 0, 0, 0 };

        // Bit 7 of byte 0 = item present (0x80)
        if (self.item != null) null_bits[0] |= 0x80;
        // Bit 0 of byte 1 = name present (0x01)
        if (self.name != null) null_bits[1] |= 0x01;
        // Bit 7 of byte 1 = cubeTextures present (0x80) - matches Java BlockType.java line 1107-1109
        if (self.cube_textures != null) null_bits[1] |= 0x80;

        // Write nullBits (4 bytes)
        try buf.appendSlice(allocator, &null_bits);

        // Fixed fields
        try buf.append(allocator, if (self.unknown) 1 else 0);
        try buf.append(allocator, @intFromEnum(self.draw_type));
        try buf.append(allocator, @intFromEnum(self.material));
        try buf.append(allocator, @intFromEnum(self.opacity));

        // hitbox (i32 LE)
        try writeI32(&buf, allocator, self.hitbox);
        // interactionHitbox (i32 LE)
        try writeI32(&buf, allocator, self.interaction_hitbox);
        // modelScale (f32 LE)
        try writeF32(&buf, allocator, self.model_scale);
        // looping (bool)
        try buf.append(allocator, if (self.looping) 1 else 0);
        // maxSupportDistance (i32 LE)
        try writeI32(&buf, allocator, self.max_support_distance);
        // blockSupportsRequiredFor (u8)
        try buf.append(allocator, @intFromEnum(self.block_supports_required_for));
        // requiresAlphaBlending (bool)
        try buf.append(allocator, if (self.requires_alpha_blending) 1 else 0);
        // cubeShadingMode (u8)
        try buf.append(allocator, @intFromEnum(self.cube_shading_mode));
        // randomRotation (u8)
        try buf.append(allocator, @intFromEnum(self.random_rotation));
        // variantRotation (u8)
        try buf.append(allocator, @intFromEnum(self.variant_rotation));
        // rotationYawPlacementOffset (u8)
        try buf.append(allocator, @intFromEnum(self.rotation_yaw_placement_offset));
        // blockSoundSetIndex (i32 LE)
        try writeI32(&buf, allocator, self.block_sound_set_index);
        // ambientSoundEventIndex (i32 LE)
        try writeI32(&buf, allocator, self.ambient_sound_event_index);

        // particleColor (3 bytes) - null, write zeros
        try buf.appendNTimes(allocator, 0, 3);
        // light (4 bytes) - null, write zeros
        try buf.appendNTimes(allocator, 0, 4);
        // tint (24 bytes) - null, write zeros
        try buf.appendNTimes(allocator, 0, 24);
        // biomeTint (24 bytes) - null, write zeros
        try buf.appendNTimes(allocator, 0, 24);

        // group (i32 LE)
        try writeI32(&buf, allocator, self.group);

        // movementSettings (42 bytes) - null, write zeros
        try buf.appendNTimes(allocator, 0, 42);
        // flags (2 bytes) - null, write zeros
        try buf.appendNTimes(allocator, 0, 2);
        // placementSettings (16 bytes) - null, write zeros
        try buf.appendNTimes(allocator, 0, 16);

        // ignoreSupportWhenPlaced (bool)
        try buf.append(allocator, if (self.ignore_support_when_placed) 1 else 0);
        // transitionToTag (i32 LE)
        try writeI32(&buf, allocator, self.transition_to_tag);

        // Record position for variable block start
        const fixed_end = buf.items.len;

        // 24 offset slots for variable fields (all -1 = not present)
        // item, name, shaderEffect, model, modelTexture, modelAnimation,
        // support, supporting, cubeTextures, cubeSideMaskTexture, particles,
        // blockParticleSetId, blockBreakingDecalId, transitionTexture,
        // transitionToGroups, interactionHint, gathering, display, rail,
        // interactions, states, tagIndexes, bench, connectedBlockRuleSet
        const item_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4); // item
        const name_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4); // name
        // Skip 6 offset slots (shaderEffect, model, modelTexture, modelAnimation, support, supporting)
        try buf.appendNTimes(allocator, 0, 24); // 6 * 4 bytes
        const cube_textures_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4); // cubeTextures

        // Remaining 15 offset slots - all -1
        // (cubeSideMaskTexture, particles, blockParticleSetId, blockBreakingDecalId,
        //  transitionTexture, transitionToGroups, interactionHint, gathering, display,
        //  rail, interactions, states, tagIndexes, bench, connectedBlockRuleSet)
        for (0..15) |_| {
            try writeI32(&buf, allocator, -1);
        }

        // Variable block start position
        const var_block_start = buf.items.len;

        // Write variable fields
        if (self.item) |item_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[item_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, item_str);
        } else {
            std.mem.writeInt(i32, buf.items[item_offset_pos..][0..4], -1, .little);
        }

        if (self.name) |name_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[name_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, name_str);
        } else {
            std.mem.writeInt(i32, buf.items[name_offset_pos..][0..4], -1, .little);
        }

        if (self.cube_textures) |*cube_tex| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[cube_textures_offset_pos..][0..4], offset, .little);
            // Write VarInt count (always 1 for single texture set)
            try writeVarInt(&buf, allocator, 1);
            // Write BlockTextures data
            const cube_data = try cube_tex.serialize(allocator);
            defer allocator.free(cube_data);
            try buf.appendSlice(allocator, cube_data);
        } else {
            std.mem.writeInt(i32, buf.items[cube_textures_offset_pos..][0..4], -1, .little);
        }

        _ = fixed_end;

        return buf.toOwnedSlice(allocator);
    }

    /// Create a simple air block
    pub fn air() Self {
        return .{
            .draw_type = .empty,
            .material = .empty,
            .opacity = .solid,
        };
    }

    /// Create a simple solid block with fallback textures
    pub fn solid(allocator: Allocator, name: ?[]const u8) !Self {
        const textures = try BlockTextures.unknown(allocator);
        return .{
            .name = name,
            .draw_type = .cube,
            .material = .solid,
            .opacity = .solid,
            .cube_textures = textures,
        };
    }
};

// Helper functions
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
    // VarInt length
    try writeVarInt(buf, allocator, @intCast(str.len));
    // String bytes
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

test "BlockTypeAsset air serialization" {
    const allocator = std.testing.allocator;

    const air_block = BlockTypeAsset.air();
    const data = try air_block.serialize(allocator);
    defer allocator.free(data);

    // Should produce valid output
    // 4 (nullBits) + 159 (fixed) + 96 (offsets) = 259 bytes minimum
    try std.testing.expect(data.len >= 259);

    // Verify nullBits: for air block, ALL nullBits should be 0
    // Byte 0: no item (bit 7 = 0)
    // Byte 1: no name (bit 0 = 0)
    // Bytes 2-3: no other nullable fields set
    try std.testing.expectEqual(@as(u8, 0), data[0]); // nullBits byte 0
    try std.testing.expectEqual(@as(u8, 0), data[1]); // nullBits byte 1 (name bit = 0)
    try std.testing.expectEqual(@as(u8, 0), data[2]); // nullBits byte 2
    try std.testing.expectEqual(@as(u8, 0), data[3]); // nullBits byte 3

    // Verify draw_type is empty (0) at byte offset 5 (after 4 nullBits + 1 unknown)
    try std.testing.expectEqual(@as(u8, 0), data[5]); // draw_type = empty
}

test "BlockTypeAsset empty block with name should fail" {
    const allocator = std.testing.allocator;

    // Create an invalid block: empty draw_type but with a name
    var invalid_block = BlockTypeAsset.air();
    invalid_block.name = "Invalid";

    // Serialization should fail with validation error
    const result = invalid_block.serialize(allocator);
    try std.testing.expectError(error.EmptyBlockCannotHaveName, result);
}

test "BlockTypeAsset solid serialization" {
    const allocator = std.testing.allocator;

    var stone = try BlockTypeAsset.solid(allocator, "Stone");
    defer if (stone.cube_textures) |*tex| tex.deinit(allocator);
    const data = try stone.serialize(allocator);
    defer allocator.free(data);

    // Should include the name string
    try std.testing.expect(data.len > 259);

    // Verify draw_type is cube (2) at byte offset 5 (after 4 nullBits + 1 unknown)
    // This must be 2 to match Java's DrawType.Cube
    try std.testing.expectEqual(@as(u8, 2), data[5]);
}

test "DrawType enum values match Java protocol" {
    // These values must match com/hypixel/hytale/protocol/DrawType.java
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(DrawType.empty));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(DrawType.gizmo_cube));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(DrawType.cube));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(DrawType.model));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(DrawType.cube_with_model));
}
