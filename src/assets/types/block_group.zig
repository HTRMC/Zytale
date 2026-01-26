/// BlockGroup Asset
///
/// Represents a named group of blocks (for game mechanics).
/// Based on com/hypixel/hytale/protocol/BlockGroup.java

const std = @import("std");
const Allocator = std.mem.Allocator;

/// BlockGroup asset
/// Format: nullBits(1) + if bit 0: VarInt count + VarString[] names
pub const BlockGroupAsset = struct {
    names: ?[]const []const u8 = null,

    const Self = @This();

    pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
    pub const FIXED_BLOCK_SIZE: u32 = 1;
    pub const VARIABLE_FIELD_COUNT: u32 = 1;
    pub const VARIABLE_BLOCK_START: u32 = 1;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.names != null) null_bits |= 0x01;
        try buf.append(allocator, null_bits);

        // names array (if present)
        if (self.names) |name_list| {
            // VarInt count
            try writeVarInt(&buf, allocator, @intCast(name_list.len));

            // Each name string
            for (name_list) |name| {
                try writeVarString(&buf, allocator, name);
            }
        }

        return buf.toOwnedSlice(allocator);
    }
};

// Helper functions
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

test "BlockGroupAsset serialization" {
    const allocator = std.testing.allocator;

    const names = [_][]const u8{
        "stone",
        "cobblestone",
        "granite",
    };

    var group = BlockGroupAsset{
        .names = &names,
    };

    const data = try group.serialize(allocator);
    defer allocator.free(data);

    // Should have nullBits + VarInt(3) + 3 strings
    try std.testing.expect(data.len >= 2);

    // Check nullBits: names present (0x01)
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);

    // Check VarInt count = 3
    try std.testing.expectEqual(@as(u8, 0x03), data[1]);
}

test "BlockGroupAsset empty" {
    const allocator = std.testing.allocator;

    var group = BlockGroupAsset{};

    const data = try group.serialize(allocator);
    defer allocator.free(data);

    // Just nullBits (1 byte)
    try std.testing.expectEqual(@as(usize, 1), data.len);

    // Check nullBits: nothing present (0x00)
    try std.testing.expectEqual(@as(u8, 0x00), data[0]);
}
