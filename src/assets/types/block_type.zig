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

/// Tint for block faces (24 bytes - 6 faces x 4 bytes each)
pub const Tint = struct {
    data: [24]u8 = [_]u8{0} ** 24,

    pub fn serialize(self: *const Tint, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.appendSlice(allocator, &self.data);
    }
};

/// Block movement settings (42 bytes)
pub const BlockMovementSettings = struct {
    data: [42]u8 = [_]u8{0} ** 42,

    pub fn serialize(self: *const BlockMovementSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.appendSlice(allocator, &self.data);
    }
};

/// Block flags (2 bytes)
pub const BlockFlags = struct {
    value: u16 = 0,

    pub fn serialize(self: *const BlockFlags, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, self.value, .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// Block placement settings (16 bytes)
pub const BlockPlacementSettings = struct {
    data: [16]u8 = [_]u8{0} ** 16,

    pub fn serialize(self: *const BlockPlacementSettings, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        try buf.appendSlice(allocator, &self.data);
    }
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
    // Optional variable fields (null = not present in nullBits)
    item: ?[]const u8 = null,
    name: ?[]const u8 = null,
    cube_textures: ?BlockTextures = null,

    // Optional inline fields (null = not present in nullBits)
    // These fields have fixed sizes but are still nullable
    particle_color: ?Color = null,
    light: ?ColorLight = null,
    tint: ?Tint = null,
    biome_tint: ?Tint = null,
    movement_settings: ?BlockMovementSettings = null,
    flags: ?BlockFlags = null,
    placement_settings: ?BlockPlacementSettings = null,

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
    /// Layout matches Java BlockType.java exactly:
    /// - Bytes 0-3: nullBits[4]
    /// - Bytes 4-162: Fixed inline fields (159 bytes)
    /// - Bytes 163-258: 24 offset slots (4 bytes each = 96 bytes)
    /// - Byte 259+: Variable block data
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        // Validation: Empty blocks (air) MUST NOT have a name
        // The client validates: if drawType == empty && name != null, it throws
        // "Block type with EmptyBlockId but has name"
        if (self.draw_type == .empty and self.name != null) {
            return error.EmptyBlockCannotHaveName;
        }

        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Calculate nullBits - must match Java BlockType.java lines 1047-1169
        var null_bits: [4]u8 = .{ 0, 0, 0, 0 };

        // Byte 0 inline fields
        if (self.particle_color != null) null_bits[0] |= 0x01; // bit 0
        if (self.light != null) null_bits[0] |= 0x02; // bit 1
        if (self.tint != null) null_bits[0] |= 0x04; // bit 2
        if (self.biome_tint != null) null_bits[0] |= 0x08; // bit 3
        if (self.movement_settings != null) null_bits[0] |= 0x10; // bit 4
        if (self.flags != null) null_bits[0] |= 0x20; // bit 5
        if (self.placement_settings != null) null_bits[0] |= 0x40; // bit 6
        if (self.item != null) null_bits[0] |= 0x80; // bit 7

        // Byte 1 variable fields
        if (self.name != null) null_bits[1] |= 0x01; // bit 0
        // shaderEffect (bit 1) - not implemented
        // model (bit 2) - not implemented
        // modelTexture (bit 3) - not implemented
        // modelAnimation (bit 4) - not implemented
        // support (bit 5) - not implemented
        // supporting (bit 6) - not implemented
        if (self.cube_textures != null) null_bits[1] |= 0x80; // bit 7

        // Byte 2 and 3 - not implemented, leave as 0

        // Write nullBits (4 bytes)
        try buf.appendSlice(allocator, &null_bits);

        // Fixed fields (159 bytes total)
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

        // particleColor (3 bytes) - serialize if present, otherwise zeros
        if (self.particle_color) |*pc| {
            try pc.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 3);
        }

        // light (4 bytes) - serialize if present, otherwise zeros
        if (self.light) |*l| {
            try l.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 4);
        }

        // tint (24 bytes) - serialize if present, otherwise zeros
        if (self.tint) |*t| {
            try t.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 24);
        }

        // biomeTint (24 bytes) - serialize if present, otherwise zeros
        if (self.biome_tint) |*bt| {
            try bt.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 24);
        }

        // group (i32 LE)
        try writeI32(&buf, allocator, self.group);

        // movementSettings (42 bytes) - serialize if present, otherwise zeros
        if (self.movement_settings) |*ms| {
            try ms.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 42);
        }

        // flags (2 bytes) - serialize if present, otherwise zeros
        if (self.flags) |*f| {
            try f.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 2);
        }

        // placementSettings (16 bytes) - serialize if present, otherwise zeros
        if (self.placement_settings) |*ps| {
            try ps.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 16);
        }

        // ignoreSupportWhenPlaced (bool)
        try buf.append(allocator, if (self.ignore_support_when_placed) 1 else 0);
        // transitionToTag (i32 LE)
        try writeI32(&buf, allocator, self.transition_to_tag);

        // At this point we should be at byte 163 (FIXED_BLOCK_SIZE)
        // Write all 24 offset slots as placeholders (initialized to 0)
        // We'll set each to -1 or actual offset afterwards
        const offset_slots_start = buf.items.len;
        try buf.appendNTimes(allocator, 0, 96); // 24 * 4 bytes

        // Variable block starts at byte 259 (VARIABLE_BLOCK_START)
        const var_block_start = buf.items.len;

        // Helper to set an offset slot value
        const setOffsetSlot = struct {
            fn call(buffer: *std.ArrayListUnmanaged(u8), slots_start: usize, slot: usize, value: i32) void {
                const pos = slots_start + (slot * 4);
                std.mem.writeInt(i32, buffer.items[pos..][0..4], value, .little);
            }
        }.call;

        // Initialize ALL 24 offset slots to -1 (null)
        // This is CRITICAL - Java does the same and the client expects -1 for null fields
        for (0..24) |slot| {
            setOffsetSlot(&buf, offset_slots_start, slot, -1);
        }

        // Slot 0: item
        if (self.item) |item_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            setOffsetSlot(&buf, offset_slots_start, 0, offset);
            try writeVarString(&buf, allocator, item_str);
        }

        // Slot 1: name
        if (self.name) |name_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            setOffsetSlot(&buf, offset_slots_start, 1, offset);
            try writeVarString(&buf, allocator, name_str);
        }

        // Slots 2-7: shaderEffect, model, modelTexture, modelAnimation, support, supporting
        // Already set to -1 above, no implementation needed

        // Slot 8: cubeTextures
        if (self.cube_textures) |*cube_tex| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            setOffsetSlot(&buf, offset_slots_start, 8, offset);
            // Write VarInt count (always 1 for single texture set)
            try writeVarInt(&buf, allocator, 1);
            // Write BlockTextures data
            const cube_data = try cube_tex.serialize(allocator);
            defer allocator.free(cube_data);
            try buf.appendSlice(allocator, cube_data);
        }

        // Slots 9-23: remaining fields - already set to -1 above

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

test "all 24 offset slots are -1 for air block" {
    const allocator = std.testing.allocator;

    const air_block = BlockTypeAsset.air();
    const data = try air_block.serialize(allocator);
    defer allocator.free(data);

    // Offset slots start at byte 163 (FIXED_BLOCK_SIZE)
    // Each slot is 4 bytes, so slots 0-23 are at bytes 163-258
    // For air block, ALL slots must be -1 (0xFFFFFFFF)
    for (0..24) |slot| {
        const slot_pos = FIXED_BLOCK_SIZE + (slot * 4);
        const slot_value = std.mem.readInt(i32, data[slot_pos..][0..4], .little);
        try std.testing.expectEqual(@as(i32, -1), slot_value);
    }
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

test "solid block has correct offset for name and cubeTextures" {
    const allocator = std.testing.allocator;

    var stone = try BlockTypeAsset.solid(allocator, "Stone");
    defer if (stone.cube_textures) |*tex| tex.deinit(allocator);
    const data = try stone.serialize(allocator);
    defer allocator.free(data);

    // Verify nullBits: name (byte 1, bit 0) and cubeTextures (byte 1, bit 7) should be set
    try std.testing.expectEqual(@as(u8, 0x81), data[1]); // name(0x01) | cubeTextures(0x80)

    // Helper to read offset slot value
    const readOffsetSlot = struct {
        fn call(buf: []const u8, slot: usize) i32 {
            const slot_pos = FIXED_BLOCK_SIZE + (slot * 4);
            return std.mem.readInt(i32, buf[slot_pos..][0..4], .little);
        }
    }.call;

    // Slot 0 (item): should be -1 (no item)
    try std.testing.expectEqual(@as(i32, -1), readOffsetSlot(data, 0));

    // Slot 1 (name): should be 0 (first variable field, starts at var block start)
    try std.testing.expectEqual(@as(i32, 0), readOffsetSlot(data, 1));

    // Slots 2-7 (shaderEffect through supporting): should ALL be -1
    for (2..8) |slot| {
        try std.testing.expectEqual(@as(i32, -1), readOffsetSlot(data, slot));
    }

    // Slot 8 (cubeTextures): should be > 0 (comes after the name string)
    const cube_textures_offset = readOffsetSlot(data, 8);
    try std.testing.expect(cube_textures_offset > 0);

    // Slots 9-23: should ALL be -1
    for (9..24) |slot| {
        try std.testing.expectEqual(@as(i32, -1), readOffsetSlot(data, slot));
    }
}

test "DrawType enum values match Java protocol" {
    // These values must match com/hypixel/hytale/protocol/DrawType.java
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(DrawType.empty));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(DrawType.gizmo_cube));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(DrawType.cube));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(DrawType.model));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(DrawType.cube_with_model));
}
