const std = @import("std");
const varint = @import("../../net/packet/varint.zig");
const constants = @import("../../world/constants.zig");
const Section = @import("../../world/section.zig").Section;
const Chunk = @import("../../world/chunk.zig").Chunk;

/// SetChunk packet (ID=131)
/// Sends a single chunk section (32x32x32) to the client
///
/// Format from SetChunk.java lines 170-239:
/// [1 byte]  nullBits (bit 0: localLight, bit 1: globalLight, bit 2: data)
/// [4 bytes] x (i32 LE) - chunk X coordinate
/// [4 bytes] y (i32 LE) - section Y index (0-9)
/// [4 bytes] z (i32 LE) - chunk Z coordinate
/// [4 bytes] localLightOffset (i32 LE) or -1
/// [4 bytes] globalLightOffset (i32 LE) or -1
/// [4 bytes] dataOffset (i32 LE) or -1
/// --- Variable data (offset 25) ---
/// [VarInt + bytes] localLight data (if bit 0)
/// [VarInt + bytes] globalLight data (if bit 1)
/// [VarInt + bytes] block section data (if bit 2)
pub const SetChunk = struct {
    chunk_x: i32,
    section_y: i32,
    chunk_z: i32,
    section_data: ?[]const u8,
    local_light: ?[]const u8,
    global_light: ?[]const u8,

    const Self = @This();

    pub const HEADER_SIZE: usize = 25;

    /// Serialize SetChunk packet payload
    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        // Calculate total size
        var data_size: usize = HEADER_SIZE;

        if (self.local_light) |light| {
            data_size += varint.varIntSize(@intCast(light.len));
            data_size += light.len;
        }
        if (self.global_light) |light| {
            data_size += varint.varIntSize(@intCast(light.len));
            data_size += light.len;
        }
        if (self.section_data) |data| {
            data_size += varint.varIntSize(@intCast(data.len));
            data_size += data.len;
        }

        const buf = try allocator.alloc(u8, data_size);
        errdefer allocator.free(buf);

        var offset: usize = 0;

        // Null bits
        var null_bits: u8 = 0;
        if (self.local_light != null) null_bits |= 0x01;
        if (self.global_light != null) null_bits |= 0x02;
        if (self.section_data != null) null_bits |= 0x04;
        buf[offset] = null_bits;
        offset += 1;

        // Coordinates
        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_x, .little);
        offset += 4;
        std.mem.writeInt(i32, buf[offset..][0..4], self.section_y, .little);
        offset += 4;
        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_z, .little);
        offset += 4;

        // Calculate offsets for variable data
        var var_offset: i32 = @intCast(HEADER_SIZE);
        var local_light_offset: i32 = -1;
        var global_light_offset: i32 = -1;
        var data_offset: i32 = -1;

        if (self.local_light) |light| {
            local_light_offset = var_offset;
            var_offset += @intCast(varint.varIntSize(@intCast(light.len)) + light.len);
        }
        if (self.global_light) |light| {
            global_light_offset = var_offset;
            var_offset += @intCast(varint.varIntSize(@intCast(light.len)) + light.len);
        }
        if (self.section_data) |data| {
            data_offset = var_offset;
            _ = data;
        }

        // Write offsets
        std.mem.writeInt(i32, buf[offset..][0..4], local_light_offset, .little);
        offset += 4;
        std.mem.writeInt(i32, buf[offset..][0..4], global_light_offset, .little);
        offset += 4;
        std.mem.writeInt(i32, buf[offset..][0..4], data_offset, .little);
        offset += 4;

        // Write variable data
        if (self.local_light) |light| {
            offset += varint.writeVarInt(@intCast(light.len), buf[offset..]);
            @memcpy(buf[offset .. offset + light.len], light);
            offset += light.len;
        }
        if (self.global_light) |light| {
            offset += varint.writeVarInt(@intCast(light.len), buf[offset..]);
            @memcpy(buf[offset .. offset + light.len], light);
            offset += light.len;
        }
        if (self.section_data) |data| {
            offset += varint.writeVarInt(@intCast(data.len), buf[offset..]);
            @memcpy(buf[offset .. offset + data.len], data);
            offset += data.len;
        }

        return buf[0..offset];
    }

    /// Create SetChunk from a Section
    pub fn fromSection(
        allocator: std.mem.Allocator,
        chunk_x: i32,
        section_y: i32,
        chunk_z: i32,
        section: *const Section,
    ) !Self {
        const section_data = try section.serialize(allocator);

        return Self{
            .chunk_x = chunk_x,
            .section_y = section_y,
            .chunk_z = chunk_z,
            .section_data = section_data,
            .local_light = null, // TODO: implement lighting
            .global_light = null,
        };
    }

    /// Create SetChunk for an empty section
    pub fn empty(chunk_x: i32, section_y: i32, chunk_z: i32) Self {
        return Self{
            .chunk_x = chunk_x,
            .section_y = section_y,
            .chunk_z = chunk_z,
            .section_data = null,
            .local_light = null,
            .global_light = null,
        };
    }
};

/// SetChunkHeightmap packet (ID=132)
/// Sends heightmap data for a chunk column
///
/// Format:
/// [1 byte]  nullBits (bit 0: heightmap present)
/// [4 bytes] x (i32 LE)
/// [4 bytes] z (i32 LE)
/// [VarInt]  heightmap length
/// [bytes]   heightmap data (2048 bytes for 32x32 i16)
pub const SetChunkHeightmap = struct {
    chunk_x: i32,
    chunk_z: i32,
    heightmap: ?[]const u8,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var size: usize = 9; // nullBits + x + z
        if (self.heightmap) |hm| {
            size += varint.varIntSize(@intCast(hm.len));
            size += hm.len;
        }

        const buf = try allocator.alloc(u8, size);
        errdefer allocator.free(buf);

        var offset: usize = 0;

        // Null bits
        buf[offset] = if (self.heightmap != null) 0x01 else 0x00;
        offset += 1;

        // Coordinates
        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_x, .little);
        offset += 4;
        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_z, .little);
        offset += 4;

        // Heightmap data
        if (self.heightmap) |hm| {
            offset += varint.writeVarInt(@intCast(hm.len), buf[offset..]);
            @memcpy(buf[offset .. offset + hm.len], hm);
            offset += hm.len;
        }

        return buf[0..offset];
    }

    pub fn fromChunk(allocator: std.mem.Allocator, chunk: *const Chunk) !Self {
        const heightmap = try chunk.serializeHeightmap(allocator);
        return Self{
            .chunk_x = chunk.x,
            .chunk_z = chunk.z,
            .heightmap = heightmap,
        };
    }
};

/// SetChunkTintmap packet (ID=133)
/// Sends grass tint colors for a chunk column
///
/// Format:
/// [1 byte]  nullBits (bit 0: tintmap present)
/// [4 bytes] x (i32 LE)
/// [4 bytes] z (i32 LE)
/// [VarInt]  tintmap length
/// [bytes]   tintmap data (4096 bytes for 32x32 u32 ARGB)
pub const SetChunkTintmap = struct {
    chunk_x: i32,
    chunk_z: i32,
    tintmap: ?[]const u8,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var size: usize = 9;
        if (self.tintmap) |tm| {
            size += varint.varIntSize(@intCast(tm.len));
            size += tm.len;
        }

        const buf = try allocator.alloc(u8, size);
        errdefer allocator.free(buf);

        var offset: usize = 0;

        buf[offset] = if (self.tintmap != null) 0x01 else 0x00;
        offset += 1;

        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_x, .little);
        offset += 4;
        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_z, .little);
        offset += 4;

        if (self.tintmap) |tm| {
            offset += varint.writeVarInt(@intCast(tm.len), buf[offset..]);
            @memcpy(buf[offset .. offset + tm.len], tm);
            offset += tm.len;
        }

        return buf[0..offset];
    }

    pub fn fromChunk(allocator: std.mem.Allocator, chunk: *const Chunk) !Self {
        const tintmap = try chunk.serializeTintmap(allocator);
        return Self{
            .chunk_x = chunk.x,
            .chunk_z = chunk.z,
            .tintmap = tintmap,
        };
    }
};

/// SetChunkEnvironments packet (ID=134)
/// Sends environment/biome data for a chunk column
///
/// Format:
/// [1 byte]  nullBits (bit 0: environments present)
/// [4 bytes] x (i32 LE)
/// [4 bytes] z (i32 LE)
/// [VarInt]  environments length
/// [bytes]   environments data (1024 bytes for 32x32 u8)
pub const SetChunkEnvironments = struct {
    chunk_x: i32,
    chunk_z: i32,
    environments: ?[]const u8,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var size: usize = 9;
        if (self.environments) |env| {
            size += varint.varIntSize(@intCast(env.len));
            size += env.len;
        }

        const buf = try allocator.alloc(u8, size);
        errdefer allocator.free(buf);

        var offset: usize = 0;

        buf[offset] = if (self.environments != null) 0x01 else 0x00;
        offset += 1;

        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_x, .little);
        offset += 4;
        std.mem.writeInt(i32, buf[offset..][0..4], self.chunk_z, .little);
        offset += 4;

        if (self.environments) |env| {
            offset += varint.writeVarInt(@intCast(env.len), buf[offset..]);
            @memcpy(buf[offset .. offset + env.len], env);
            offset += env.len;
        }

        return buf[0..offset];
    }

    pub fn fromChunk(allocator: std.mem.Allocator, chunk: *const Chunk) !Self {
        const environments = try chunk.serializeEnvironments(allocator);
        return Self{
            .chunk_x = chunk.x,
            .chunk_z = chunk.z,
            .environments = environments,
        };
    }
};

/// JoinWorld packet (ID=104)
/// Signals client to enter a world
///
/// Format:
/// [1 byte]   clearWorld (bool)
/// [1 byte]   fadeInOut (bool)
/// [16 bytes] worldUuid (UUID)
pub const JoinWorld = struct {
    clear_world: bool,
    fade_in_out: bool,
    world_uuid: [16]u8,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, 18);

        buf[0] = if (self.clear_world) 1 else 0;
        buf[1] = if (self.fade_in_out) 1 else 0;
        @memcpy(buf[2..18], &self.world_uuid);

        return buf;
    }
};

test "set chunk serialization" {
    const allocator = std.testing.allocator;

    const packet = SetChunk{
        .chunk_x = 5,
        .section_y = 2,
        .chunk_z = -3,
        .section_data = null,
        .local_light = null,
        .global_light = null,
    };

    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    // Check header
    try std.testing.expectEqual(@as(u8, 0x00), data[0]); // no data
    try std.testing.expectEqual(@as(i32, 5), std.mem.readInt(i32, data[1..5], .little));
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, data[5..9], .little));
    try std.testing.expectEqual(@as(i32, -3), std.mem.readInt(i32, data[9..13], .little));
}

test "join world serialization" {
    const allocator = std.testing.allocator;

    const uuid = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0 };

    const packet = JoinWorld{
        .clear_world = true,
        .fade_in_out = false,
        .world_uuid = uuid,
    };

    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 18), data.len);
    try std.testing.expectEqual(@as(u8, 1), data[0]);
    try std.testing.expectEqual(@as(u8, 0), data[1]);
    try std.testing.expect(std.mem.eql(u8, &uuid, data[2..18]));
}
