/// UpdateFluids Packet (ID 83)
///
/// Sends fluid definitions to the client.

const std = @import("std");
const serializer = @import("serializer.zig");
const fluid = @import("../../../assets/types/fluid.zig");

pub const FluidAsset = fluid.FluidAsset;

// Constants from Java UpdateFluids.java
pub const PACKET_ID: u32 = 83;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 6;
pub const VARIABLE_FIELD_COUNT: u32 = 1;
pub const VARIABLE_BLOCK_START: u32 = 6;
pub const MAX_SIZE: u32 = 1677721600;

/// Fluid entry for serialization
pub const FluidEntry = struct {
    id: u32,
    fluid: FluidAsset,
};

/// Serialize UpdateFluids packet
/// Format:
/// - nullBits (1 byte): bit 0 = fluids dictionary present
/// - type (1 byte): UpdateType enum
/// - maxId (4 bytes LE): maximum fluid ID
/// - If bit 0 set: VarInt count + for each: i32 key + Fluid data
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: u32,
    entries: []const FluidEntry,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits: bit 0 = fluids present
    const null_bits: u8 = if (entries.len > 0) 0x01 else 0x00;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // maxId (i32 LE)
    var max_id_bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &max_id_bytes, @intCast(max_id), .little);
    try buf.appendSlice(allocator, &max_id_bytes);

    // fluids dictionary (if present)
    if (entries.len > 0) {
        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: i32 key + Fluid data
        for (entries) |entry| {
            // Key (i32 LE)
            var key_bytes: [4]u8 = undefined;
            std.mem.writeInt(i32, &key_bytes, @intCast(entry.id), .little);
            try buf.appendSlice(allocator, &key_bytes);

            // Fluid data
            const fluid_data = try entry.fluid.serialize(allocator);
            defer allocator.free(fluid_data);
            try buf.appendSlice(allocator, fluid_data);
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (7 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
}

test "UpdateFluids empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
}

test "UpdateFluids with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]FluidEntry{
        .{ .id = 1, .fluid = .{ .id = "water", .max_fluid_level = 8 } },
    };

    const pkt = try serialize(allocator, .init, 1, &entries);
    defer allocator.free(pkt);

    // Should have header + 1 fluid
    try std.testing.expect(pkt.len > 7);

    // Check nullBits has dictionary present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check maxId is 1
    try std.testing.expectEqual(@as(i32, 1), std.mem.readInt(i32, pkt[2..6], .little));
}
