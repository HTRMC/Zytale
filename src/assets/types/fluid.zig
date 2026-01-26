/// Fluid Asset
///
/// Represents a fluid type (water, lava, etc.)
/// Based on com/hypixel/hytale/protocol/Fluid.java

const std = @import("std");
const Allocator = std.mem.Allocator;
const block_type = @import("block_type.zig");

pub const BlockTextures = block_type.BlockTextures;
pub const Opacity = block_type.Opacity;

/// Color (RGB)
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

/// ColorLight (RGBA as u32)
pub const ColorLight = struct {
    value: u32 = 0,

    pub fn serialize(self: *const ColorLight, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, self.value, .little);
        try buf.appendSlice(allocator, &bytes);
    }
};

/// Shader effect type
pub const ShaderType = enum(u8) {
    none = 0,
    // Add more as needed

    pub fn fromValue(value: u8) ShaderType {
        return @enumFromInt(value);
    }
};

/// Fluid asset
pub const FluidAsset = struct {
    id: ?[]const u8 = null,
    max_fluid_level: i32 = 8,
    cube_textures: ?BlockTextures = null,
    requires_alpha_blending: bool = false,
    opacity: Opacity = .solid,
    shader_effect: ?[]const ShaderType = null,
    light: ?ColorLight = null,
    fluid_fx_index: i32 = -1,
    block_sound_set_index: i32 = -1,
    block_particle_set_id: ?[]const u8 = null,
    particle_color: ?Color = null,
    tag_indexes: ?[]const i32 = null,

    const Self = @This();

    /// Protocol constants from Java
    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 22;
    pub const VARIABLE_FIELD_COUNT: u32 = 5;
    pub const VARIABLE_BLOCK_START: u32 = 42;

    /// Serialize to protocol format
    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // Calculate nullBits
        var null_bits: u8 = 0;
        if (self.light != null) null_bits |= 0x01;
        if (self.particle_color != null) null_bits |= 0x02;
        if (self.id != null) null_bits |= 0x04;
        if (self.cube_textures != null) null_bits |= 0x08;
        if (self.shader_effect != null) null_bits |= 0x10;
        if (self.block_particle_set_id != null) null_bits |= 0x20;
        if (self.tag_indexes != null) null_bits |= 0x40;

        // Write nullBits (1 byte)
        try buf.append(allocator, null_bits);

        // Write maxFluidLevel (i32 LE)
        try writeI32(&buf, allocator, self.max_fluid_level);

        // Write requiresAlphaBlending (bool)
        try buf.append(allocator, if (self.requires_alpha_blending) 1 else 0);

        // Write opacity (u8)
        try buf.append(allocator, @intFromEnum(self.opacity));

        // Write light (4 bytes) or zeros
        if (self.light) |light| {
            try light.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 4);
        }

        // Write fluidFXIndex (i32 LE)
        try writeI32(&buf, allocator, self.fluid_fx_index);

        // Write blockSoundSetIndex (i32 LE)
        try writeI32(&buf, allocator, self.block_sound_set_index);

        // Write particleColor (3 bytes) or zeros
        if (self.particle_color) |color| {
            try color.serialize(&buf, allocator);
        } else {
            try buf.appendNTimes(allocator, 0, 3);
        }

        // Write 5 offset slots (20 bytes)
        const id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const cube_textures_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const shader_effect_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const block_particle_set_id_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);
        const tag_indexes_offset_pos = buf.items.len;
        try buf.appendNTimes(allocator, 0, 4);

        // Variable block start position (offset 42)
        const var_block_start = buf.items.len;

        // Write variable fields
        if (self.id) |id_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id_str);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_pos..][0..4], -1, .little);
        }

        if (self.cube_textures) |*cube_tex| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[cube_textures_offset_pos..][0..4], offset, .little);
            // Write VarInt count (1)
            try writeVarInt(&buf, allocator, 1);
            // Write BlockTextures data
            const cube_data = try cube_tex.serialize(allocator);
            defer allocator.free(cube_data);
            try buf.appendSlice(allocator, cube_data);
        } else {
            std.mem.writeInt(i32, buf.items[cube_textures_offset_pos..][0..4], -1, .little);
        }

        if (self.shader_effect) |effects| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[shader_effect_offset_pos..][0..4], offset, .little);
            // Write VarInt count
            try writeVarInt(&buf, allocator, @intCast(effects.len));
            // Write each shader type
            for (effects) |effect| {
                try buf.append(allocator, @intFromEnum(effect));
            }
        } else {
            std.mem.writeInt(i32, buf.items[shader_effect_offset_pos..][0..4], -1, .little);
        }

        if (self.block_particle_set_id) |id_str| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[block_particle_set_id_offset_pos..][0..4], offset, .little);
            try writeVarString(&buf, allocator, id_str);
        } else {
            std.mem.writeInt(i32, buf.items[block_particle_set_id_offset_pos..][0..4], -1, .little);
        }

        if (self.tag_indexes) |indexes| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[tag_indexes_offset_pos..][0..4], offset, .little);
            // Write VarInt count
            try writeVarInt(&buf, allocator, @intCast(indexes.len));
            // Write each index
            for (indexes) |idx| {
                try writeI32(&buf, allocator, idx);
            }
        } else {
            std.mem.writeInt(i32, buf.items[tag_indexes_offset_pos..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.id) |s| allocator.free(s);
        if (self.cube_textures) |*tex| tex.deinit(allocator);
        if (self.shader_effect) |arr| allocator.free(arr);
        if (self.block_particle_set_id) |s| allocator.free(s);
        if (self.tag_indexes) |arr| allocator.free(arr);
    }

    /// Create a default water fluid
    pub fn water(allocator: Allocator) !Self {
        return .{
            .id = try allocator.dupe(u8, "water"),
            .max_fluid_level = 8,
            .opacity = .transparent,
            .requires_alpha_blending = true,
        };
    }
};

// Helper functions
fn writeI32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, value: i32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &bytes, value, .little);
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

test "FluidAsset serialization" {
    const allocator = std.testing.allocator;

    var fluid = FluidAsset{
        .id = "water",
        .max_fluid_level = 8,
        .opacity = .transparent,
    };

    const data = try fluid.serialize(allocator);
    defer allocator.free(data);

    // Should produce minimum 42 bytes (fixed) + variable data
    try std.testing.expect(data.len >= 42);

    // Check nullBits: id set (0x04)
    try std.testing.expectEqual(@as(u8, 0x04), data[0]);

    // Check maxFluidLevel at offset 1
    try std.testing.expectEqual(@as(i32, 8), std.mem.readInt(i32, data[1..5], .little));
}
