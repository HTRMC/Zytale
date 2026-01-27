/// UpdateBlockTypes Packet (ID 40)
///
/// Sends block type definitions to the client.

const std = @import("std");
const serializer = @import("serializer.zig");
const block_type = @import("../../../assets/types/block_type.zig");

pub const BlockTypeAsset = block_type.BlockTypeAsset;

// Constants from Java UpdateBlockTypes.java
pub const PACKET_ID: u32 = 40;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 10;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 10;
pub const MAX_SIZE: u32 = 1677721600;

/// Block type entry for serialization
pub const BlockTypeEntry = struct {
    id: u32,
    block_type: BlockTypeAsset,
};

/// Serialize UpdateBlockTypes packet
/// Format:
/// - nullBits (1 byte): bit 0 = blockTypes dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes LE): maximum block ID
/// - updateBlockTextures (1 byte bool)
/// - updateModelTextures (1 byte bool)
/// - updateModels (1 byte bool)
/// - updateMapGeometry (1 byte bool)
/// - If nullBits & 1: VarInt count + for each: i32 key + BlockType data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: u32,
    entries: ?[]const BlockTypeEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = blockTypes present
    const null_bits: u8 = if (entries != null) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, @intCast(max_id), .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // updateBlockTextures, updateModelTextures, updateModels, updateMapGeometry
    // All true for init packets
    try buf.append(allocator, 1); // updateBlockTextures
    try buf.append(allocator, 1); // updateModelTextures
    try buf.append(allocator, 1); // updateModels
    try buf.append(allocator, 1); // updateMapGeometry

    // blockTypes dictionary (if present)
    if (entries) |ents| {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(ents.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + BlockType data
        for (ents) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, @intCast(entry.id), .little);
            try buf.appendSlice(allocator, &key_bytes);

            // BlockType data
            const block_data = try entry.block_type.serialize(allocator);
            defer allocator.free(block_data);
            try buf.appendSlice(allocator, block_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test "UpdateBlockTypes empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try serialize(allocator, .init, 0, null);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 10), pkt.len);
}

test "UpdateBlockTypes with entries" {
    const allocator = std.testing.allocator;

    var block1 = try BlockTypeAsset.solid(allocator, null);
    defer if (block1.cube_textures) |*tex| tex.deinit(allocator);
    const entries = [_]BlockTypeEntry{
        .{ .id = 0, .block_type = BlockTypeAsset.air() },
        .{ .id = 1, .block_type = block1 },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Should have header + 2 block types
    try std.testing.expect(pkt.len > 11);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check maxId is 1
    try std.testing.expectEqual(@as(i32, 1), std.mem.readInt(i32, pkt[2..6], .little));
}

test "UpdateBlockTypes block 0 (air) has correct nullBits" {
    const allocator = std.testing.allocator;

    // Send only air block (block 0)
    const entries = [_]BlockTypeEntry{
        .{ .id = 0, .block_type = BlockTypeAsset.air() },
    };

    const pkt = try serialize(allocator, .init, 0, &entries);
    defer allocator.free(pkt);

    // Packet structure:
    // [0]: packet nullBits (0x01 = dict present)
    // [1]: type (0x00 = init)
    // [2-5]: maxId (i32 LE)
    // [6]: updateBlockTextures
    // [7]: updateModelTextures
    // [8]: updateModels
    // [9]: updateMapGeometry
    // [10]: VarInt count (1)
    // [11-14]: entry key (i32 = 0)
    // [15-18]: BlockType nullBits
    // [19]: unknown
    // [20]: draw_type (should be 0 = empty)

    // Verify packet-level nullBits
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Verify entry count (VarInt 1)
    try std.testing.expectEqual(@as(u8, 1), pkt[10]);

    // Verify block ID 0
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[11..15], .little));

    // Verify BlockType nullBits for air block
    // Air blocks have NO name and NO cube textures
    try std.testing.expectEqual(@as(u8, 0), pkt[15]); // nullBits[0]: no item
    try std.testing.expectEqual(@as(u8, 0x00), pkt[16]); // nullBits[1]: no name, no cubeTextures
    try std.testing.expectEqual(@as(u8, 0), pkt[17]); // nullBits[2]
    try std.testing.expectEqual(@as(u8, 0), pkt[18]); // nullBits[3]

    // Verify draw_type = empty (0) at offset 19 (after 4 nullBits bytes)
    try std.testing.expectEqual(@as(u8, 0), pkt[19]); // unknown = false
    try std.testing.expectEqual(@as(u8, 0), pkt[20]); // draw_type = empty
}

test "UpdateBlockTypes solid block (no air) has correct bytes" {
    const allocator = std.testing.allocator;

    // Send only solid block (block 1) - simulating registry without block 0
    var block1 = try BlockTypeAsset.solid(allocator, "Bedrock");
    defer if (block1.cube_textures) |*tex| tex.deinit(allocator);
    const entries = [_]BlockTypeEntry{
        .{ .id = 1, .block_type = block1 },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Packet structure:
    // [0]: packet nullBits (0x01 = dict present)
    // [1]: type (0x00 = init)
    // [2-5]: maxId (i32 LE = 1)
    // [6]: updateBlockTextures (1)
    // [7]: updateModelTextures (1)
    // [8]: updateModels (1)
    // [9]: updateMapGeometry (1)
    // [10]: VarInt count (1)
    // [11-14]: entry key (i32 = 1)
    // [15-18]: BlockType nullBits
    // [19]: unknown (must be 0!)
    // [20]: draw_type (must be 2 = cube!)

    // Verify packet-level nullBits
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Verify type = init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Verify maxId = 1
    try std.testing.expectEqual(@as(i32, 1), std.mem.readInt(i32, pkt[2..6], .little));

    // Verify entry count (VarInt 1)
    try std.testing.expectEqual(@as(u8, 1), pkt[10]);

    // Verify block ID 1
    try std.testing.expectEqual(@as(i32, 1), std.mem.readInt(i32, pkt[11..15], .little));

    // Verify BlockType nullBits for Bedrock
    // nullBits[0] = 0x00 (no item)
    // nullBits[1] = 0x81 (name present bit 0 + cubeTextures present bit 7)
    // nullBits[2] = 0x00
    // nullBits[3] = 0x00
    try std.testing.expectEqual(@as(u8, 0x00), pkt[15]); // nullBits[0]
    try std.testing.expectEqual(@as(u8, 0x81), pkt[16]); // nullBits[1]: name bit + cubeTextures bit
    try std.testing.expectEqual(@as(u8, 0x00), pkt[17]); // nullBits[2]
    try std.testing.expectEqual(@as(u8, 0x00), pkt[18]); // nullBits[3]

    // CRITICAL: Verify unknown = false (0) at offset 19
    // If this is non-zero, client sees "UnknownBlockId"
    try std.testing.expectEqual(@as(u8, 0), pkt[19]); // unknown = false

    // CRITICAL: Verify draw_type = cube (2) at offset 20
    // If this is 0, client sees "EmptyBlockId"
    try std.testing.expectEqual(@as(u8, 2), pkt[20]); // draw_type = cube

    // Verify material = solid (1) at offset 21
    try std.testing.expectEqual(@as(u8, 1), pkt[21]); // material = solid

    // Verify opacity = solid (0) at offset 22
    try std.testing.expectEqual(@as(u8, 0), pkt[22]); // opacity = solid
}

test "UpdateBlockTypes registry simulation (5 blocks including air)" {
    const allocator = std.testing.allocator;

    // Simulate exactly what generateBlockTypesPacket does in registry.zig
    var block1 = try BlockTypeAsset.solid(allocator, "Bedrock");
    defer if (block1.cube_textures) |*tex| tex.deinit(allocator);
    var block2 = try BlockTypeAsset.solid(allocator, "Stone");
    defer if (block2.cube_textures) |*tex| tex.deinit(allocator);
    var block3 = try BlockTypeAsset.solid(allocator, "Dirt");
    defer if (block3.cube_textures) |*tex| tex.deinit(allocator);
    var block4 = try BlockTypeAsset.solid(allocator, "Grass");
    defer if (block4.cube_textures) |*tex| tex.deinit(allocator);

    const entries = [_]BlockTypeEntry{
        .{ .id = 0, .block_type = BlockTypeAsset.air() },
        .{ .id = 1, .block_type = block1 },
        .{ .id = 2, .block_type = block2 },
        .{ .id = 3, .block_type = block3 },
        .{ .id = 4, .block_type = block4 },
    };

    const pkt = try serialize(allocator, .init, 4, &entries);
    defer allocator.free(pkt);

    // Packet header verification
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits: dict present
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type = init
    try std.testing.expectEqual(@as(i32, 4), std.mem.readInt(i32, pkt[2..6], .little)); // maxId = 4
    try std.testing.expectEqual(@as(u8, 1), pkt[6]); // updateBlockTextures
    try std.testing.expectEqual(@as(u8, 1), pkt[7]); // updateModelTextures
    try std.testing.expectEqual(@as(u8, 1), pkt[8]); // updateModels
    try std.testing.expectEqual(@as(u8, 1), pkt[9]); // updateMapGeometry
    try std.testing.expectEqual(@as(u8, 5), pkt[10]); // VarInt count = 5

    // First entry: Block 0 (air)
    // [11-14]: key = 0
    // [15-18]: nullBits = 0x00 0x00 0x00 0x00 (no fields)
    // [19]: unknown = 0
    // [20]: draw_type = 0 (empty)
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[11..15], .little)); // block ID 0
    try std.testing.expectEqual(@as(u8, 0x00), pkt[15]); // nullBits[0]
    try std.testing.expectEqual(@as(u8, 0x00), pkt[16]); // nullBits[1] - NO name flag!
    try std.testing.expectEqual(@as(u8, 0x00), pkt[17]); // nullBits[2]
    try std.testing.expectEqual(@as(u8, 0x00), pkt[18]); // nullBits[3]
    try std.testing.expectEqual(@as(u8, 0), pkt[19]); // unknown = false
    try std.testing.expectEqual(@as(u8, 0), pkt[20]); // draw_type = empty (0)
    try std.testing.expectEqual(@as(u8, 0), pkt[21]); // material = empty (0)
    try std.testing.expectEqual(@as(u8, 0), pkt[22]); // opacity = solid (0)

    // Verify the CRITICAL condition is met for air block:
    // If draw_type == empty (0), then nullBits[1] bit 0 MUST be 0 (no name)
    const air_draw_type = pkt[20];
    const air_has_name = (pkt[16] & 0x01) != 0;
    if (air_draw_type == 0 and air_has_name) {
        // This would cause "Block type with EmptyBlockId but has name" error
        return error.InvalidAirBlockHasName;
    }

    // Verify entry boundaries:
    // Entry 0 (air): key at 11-14, BlockType data at 15-273 (259 bytes)
    // Entry 1 (bedrock): key at 274-277, BlockType data at 278+
    const air_block_data_start = 15; // After packet header and entry 0 key
    const air_block_data_size = 259; // Air block with no variable fields
    const entry1_key_pos = air_block_data_start + air_block_data_size;

    // Verify entry 1 key (Bedrock, id = 1)
    try std.testing.expectEqual(@as(i32, 1), std.mem.readInt(i32, pkt[entry1_key_pos..][0..4], .little));

    // Verify entry 1 BlockType data (Bedrock)
    const entry1_data_start = entry1_key_pos + 4;
    const entry1_nullbits = pkt[entry1_data_start .. entry1_data_start + 4];
    // nullBits[0] = 0x00 (no item)
    // nullBits[1] = 0x81 (name present bit 0 + cubeTextures present bit 7)
    try std.testing.expectEqual(@as(u8, 0x00), entry1_nullbits[0]);
    try std.testing.expectEqual(@as(u8, 0x81), entry1_nullbits[1]);
    // Verify draw_type = cube (2) for Bedrock
    try std.testing.expectEqual(@as(u8, 2), pkt[entry1_data_start + 5]); // draw_type at offset 5 from BlockType start
}

test "UpdateBlockTypes all entries validated for EmptyBlockId+name constraint" {
    const allocator = std.testing.allocator;

    // Simulate the exact packet we send to the client
    var block1 = try BlockTypeAsset.solid(allocator, "Bedrock");
    defer if (block1.cube_textures) |*tex| tex.deinit(allocator);
    var block2 = try BlockTypeAsset.solid(allocator, "Stone");
    defer if (block2.cube_textures) |*tex| tex.deinit(allocator);
    var block3 = try BlockTypeAsset.solid(allocator, "Dirt");
    defer if (block3.cube_textures) |*tex| tex.deinit(allocator);
    var block4 = try BlockTypeAsset.solid(allocator, "Grass");
    defer if (block4.cube_textures) |*tex| tex.deinit(allocator);

    const entries_data = [_]BlockTypeEntry{
        .{ .id = 0, .block_type = BlockTypeAsset.air() },
        .{ .id = 1, .block_type = block1 },
        .{ .id = 2, .block_type = block2 },
        .{ .id = 3, .block_type = block3 },
        .{ .id = 4, .block_type = block4 },
    };

    const pkt = try serialize(allocator, .init, 4, &entries_data);
    defer allocator.free(pkt);

    // Calculate sizes of each serialized block
    var block_sizes: [5]usize = undefined;
    for (0..5) |i| {
        const block_data = try entries_data[i].block_type.serialize(allocator);
        block_sizes[i] = block_data.len;
        allocator.free(block_data);
    }

    // Packet header: 11 bytes
    // Entry format: 4 bytes key + BlockType data
    var pos: usize = 11; // After header

    for (0..5) |entry_idx| {
        // Read block ID (4 bytes)
        const block_id = std.mem.readInt(i32, pkt[pos..][0..4], .little);
        try std.testing.expectEqual(@as(i32, @intCast(entry_idx)), block_id);
        pos += 4;

        // Read BlockType nullBits (4 bytes)
        const null_bits = pkt[pos .. pos + 4];
        pos += 4;

        // Read draw_type (byte 5 from BlockType start = position 4 + 1)
        // Skip unknown byte (byte 0 after nullBits)
        pos += 1;

        const actual_draw_type = pkt[pos]; // draw_type (byte 1 after nullBits)
        pos += 1;

        // Check constraint: if draw_type == 0 (Empty), name bit must be 0
        const has_name = (null_bits[1] & 0x01) != 0;
        if (actual_draw_type == 0) {
            // This is an empty block (like air) - must NOT have name
            try std.testing.expect(!has_name);
        } else {
            // Non-empty block (like Bedrock) - CAN have name
            // For our solid blocks, they SHOULD have names
            if (entry_idx > 0) {
                try std.testing.expect(has_name);
            }
        }

        // Skip to next entry (remaining block data)
        const remaining = block_sizes[entry_idx] - 6; // Already read 4 nullBits + 2 (unknown + draw_type)
        pos += remaining;
    }

    // Verify we consumed the entire packet
    try std.testing.expectEqual(pkt.len, pos);
}
