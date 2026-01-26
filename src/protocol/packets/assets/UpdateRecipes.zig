/// UpdateRecipes Packet (ID 60)
///
/// Sends recipe definitions to the client.
/// Uses string-keyed dictionary with offset-based variable fields.

const std = @import("std");
const serializer = @import("serializer.zig");
const crafting_recipe = @import("../../../assets/types/crafting_recipe.zig");

pub const CraftingRecipeAsset = crafting_recipe.CraftingRecipeAsset;

// Constants from Java UpdateRecipes.java
pub const PACKET_ID: u32 = 60;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 2;
pub const VARIABLE_FIELD_COUNT: u32 = 2;
pub const VARIABLE_BLOCK_START: u32 = 10;
pub const MAX_SIZE: u32 = 1677721600;

/// Recipe entry for serialization (string-keyed)
pub const RecipeEntry = struct {
    key: []const u8,
    recipe: CraftingRecipeAsset,
};

/// Serialize UpdateRecipes packet
/// Format (offset-based variable fields):
/// - nullBits (1 byte): bit 0 = recipes present, bit 1 = removedRecipes present
/// - type (1 byte): UpdateType enum
/// - recipesOffset (4 bytes): i32 LE offset to recipes data
/// - removedRecipesOffset (4 bytes): i32 LE offset to removedRecipes data
/// - Variable block: recipes dictionary, removedRecipes array
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    entries: []const RecipeEntry,
    removed_recipes: ?[]const []const u8,
) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    // nullBits
    var null_bits: u8 = 0;
    if (entries.len > 0) null_bits |= 0x01;
    if (removed_recipes != null and removed_recipes.?.len > 0) null_bits |= 0x02;
    try buf.append(allocator, null_bits);

    // type (UpdateType)
    try buf.append(allocator, @intFromEnum(update_type));

    // Reserve offset slots (8 bytes)
    const recipes_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const removed_offset_slot = buf.items.len;
    try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

    const var_block_start = buf.items.len;

    // recipes dictionary (if present)
    if (entries.len > 0) {
        const offset: i32 = @intCast(buf.items.len - var_block_start);
        std.mem.writeInt(i32, buf.items[recipes_offset_slot..][0..4], offset, .little);

        // VarInt count
        var vi_buf: [5]u8 = undefined;
        const vi_len = serializer.writeVarInt(&vi_buf, @intCast(entries.len));
        try buf.appendSlice(allocator, vi_buf[0..vi_len]);

        // Each entry: VarString key + CraftingRecipe data
        for (entries) |entry| {
            // Key (VarString)
            const key_vi_len = serializer.writeVarInt(&vi_buf, @intCast(entry.key.len));
            try buf.appendSlice(allocator, vi_buf[0..key_vi_len]);
            try buf.appendSlice(allocator, entry.key);

            // Recipe data
            const recipe_data = try entry.recipe.serialize(allocator);
            defer allocator.free(recipe_data);
            try buf.appendSlice(allocator, recipe_data);
        }
    } else {
        std.mem.writeInt(i32, buf.items[recipes_offset_slot..][0..4], -1, .little);
    }

    // removedRecipes array (if present)
    if (removed_recipes) |removed| {
        if (removed.len > 0) {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[removed_offset_slot..][0..4], offset, .little);

            // VarInt count
            var vi_buf: [5]u8 = undefined;
            const vi_len = serializer.writeVarInt(&vi_buf, @intCast(removed.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            // Each string
            for (removed) |name| {
                const name_vi_len = serializer.writeVarInt(&vi_buf, @intCast(name.len));
                try buf.appendSlice(allocator, vi_buf[0..name_vi_len]);
                try buf.appendSlice(allocator, name);
            }
        } else {
            std.mem.writeInt(i32, buf.items[removed_offset_slot..][0..4], -1, .little);
        }
    } else {
        std.mem.writeInt(i32, buf.items[removed_offset_slot..][0..4], -1, .little);
    }

    return buf.toOwnedSlice(allocator);
}

/// Build empty packet (12 bytes)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 12);
    buf[0] = 0x03; // nullBits: both fields present (for empty arrays)
    buf[1] = 0x00; // type = Init
    std.mem.writeInt(i32, buf[2..6], 0, .little); // offset to field 0
    std.mem.writeInt(i32, buf[6..10], 1, .little); // offset to field 1
    buf[10] = 0x00; // field 0 count = 0
    buf[11] = 0x00; // field 1 count = 0
    return buf;
}

test "UpdateRecipes empty packet size" {
    const allocator = std.testing.allocator;
    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);
    try std.testing.expectEqual(@as(usize, 12), pkt.len);
}

test "UpdateRecipes with entries" {
    const allocator = std.testing.allocator;

    const entries = [_]RecipeEntry{
        .{ .key = "sword", .recipe = .{ .time_seconds = 5.0 } },
    };

    const pkt = try serialize(allocator, .init, &entries, null);
    defer allocator.free(pkt);

    // Check nullBits has recipes present
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]);

    // Check type is init
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]);

    // Check recipes offset is 0
    const recipes_offset = std.mem.readInt(i32, pkt[2..6], .little);
    try std.testing.expectEqual(@as(i32, 0), recipes_offset);

    // Check removed offset is -1
    const removed_offset = std.mem.readInt(i32, pkt[6..10], .little);
    try std.testing.expectEqual(@as(i32, -1), removed_offset);
}
