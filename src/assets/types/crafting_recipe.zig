/// CraftingRecipe Asset Type
///
/// Represents crafting recipes with inputs, outputs, and bench requirements.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Bench type for crafting
pub const BenchType = enum(u8) {
    crafting = 0,
    processing = 1,
    diagram_crafting = 2,
    structural_crafting = 3,
};

/// Material quantity (17 bytes fixed + variable strings)
pub const MaterialQuantity = struct {
    item_id: ?[]const u8 = null,
    item_tag: i32 = 0,
    resource_type_id: ?[]const u8 = null,
    quantity: i32 = 1,

    pub const FIXED_BLOCK_SIZE: u32 = 9;
    pub const VARIABLE_BLOCK_START: u32 = 17;

    pub fn serialize(self: MaterialQuantity, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.item_id != null) null_bits |= 0x01;
        if (self.resource_type_id != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // itemTag (i32 LE)
        var tag_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &tag_bytes, self.item_tag, .little);
        try buf.appendSlice(allocator, &tag_bytes);

        // quantity (i32 LE)
        var qty_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &qty_bytes, self.quantity, .little);
        try buf.appendSlice(allocator, &qty_bytes);

        // Reserve offset slots (8 bytes)
        const item_id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const resource_type_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // itemId (if present)
        if (self.item_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[item_id_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[item_id_offset_slot..][0..4], -1, .little);
        }

        // resourceTypeId (if present)
        if (self.resource_type_id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[resource_type_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[resource_type_offset_slot..][0..4], -1, .little);
        }
    }
};

/// Bench requirement (14 bytes fixed + variable)
pub const BenchRequirement = struct {
    bench_type: BenchType = .crafting,
    id: ?[]const u8 = null,
    categories: ?[]const []const u8 = null,
    required_tier_level: i32 = 0,

    pub const FIXED_BLOCK_SIZE: u32 = 6;
    pub const VARIABLE_BLOCK_START: u32 = 14;

    pub fn serialize(self: BenchRequirement, buf: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
        const start_pos = buf.items.len;

        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.categories != null) null_bits |= 0x02;
        try buf.append(allocator, null_bits);

        // type (1 byte)
        try buf.append(allocator, @intFromEnum(self.bench_type));

        // requiredTierLevel (i32 LE)
        var tier_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &tier_bytes, self.required_tier_level, .little);
        try buf.appendSlice(allocator, &tier_bytes);

        // Reserve offset slots (8 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const categories_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = start_pos + VARIABLE_BLOCK_START;

        // id (if present)
        if (self.id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], -1, .little);
        }

        // categories (if present)
        if (self.categories) |cats| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[categories_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(cats.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (cats) |cat| {
                const cat_vi_len = writeVarIntBuf(&vi_buf, @intCast(cat.len));
                try buf.appendSlice(allocator, vi_buf[0..cat_vi_len]);
                try buf.appendSlice(allocator, cat);
            }
        } else {
            std.mem.writeInt(i32, buf.items[categories_offset_slot..][0..4], -1, .little);
        }
    }
};

/// CraftingRecipe asset (30 bytes fixed + variable)
pub const CraftingRecipeAsset = struct {
    id: ?[]const u8 = null,
    inputs: ?[]const MaterialQuantity = null,
    outputs: ?[]const MaterialQuantity = null,
    primary_output: ?MaterialQuantity = null,
    bench_requirement: ?[]const BenchRequirement = null,
    knowledge_required: bool = false,
    time_seconds: f32 = 0.0,
    required_memories_level: i32 = 0,

    const Self = @This();

    pub const FIXED_BLOCK_SIZE: u32 = 10;
    pub const VARIABLE_BLOCK_START: u32 = 30;

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        // nullBits
        var null_bits: u8 = 0;
        if (self.id != null) null_bits |= 0x01;
        if (self.inputs != null) null_bits |= 0x02;
        if (self.outputs != null) null_bits |= 0x04;
        if (self.primary_output != null) null_bits |= 0x08;
        if (self.bench_requirement != null) null_bits |= 0x10;
        try buf.append(allocator, null_bits);

        // knowledgeRequired (1 byte bool)
        try buf.append(allocator, if (self.knowledge_required) @as(u8, 1) else 0);

        // timeSeconds (f32 LE)
        var time_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &time_bytes, @bitCast(self.time_seconds), .little);
        try buf.appendSlice(allocator, &time_bytes);

        // requiredMemoriesLevel (i32 LE)
        var mem_bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &mem_bytes, self.required_memories_level, .little);
        try buf.appendSlice(allocator, &mem_bytes);

        // Reserve 5 offset slots (20 bytes)
        const id_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const inputs_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const outputs_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const primary_output_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const bench_req_offset_slot = buf.items.len;
        try buf.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });

        const var_block_start = buf.items.len;

        // id (if present)
        if (self.id) |id| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(id.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);
            try buf.appendSlice(allocator, id);
        } else {
            std.mem.writeInt(i32, buf.items[id_offset_slot..][0..4], -1, .little);
        }

        // inputs (if present)
        if (self.inputs) |inputs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[inputs_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(inputs.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (inputs) |input| {
                try input.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[inputs_offset_slot..][0..4], -1, .little);
        }

        // outputs (if present)
        if (self.outputs) |outputs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[outputs_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(outputs.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (outputs) |output| {
                try output.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[outputs_offset_slot..][0..4], -1, .little);
        }

        // primaryOutput (if present)
        if (self.primary_output) |po| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[primary_output_offset_slot..][0..4], offset, .little);
            try po.serialize(&buf, allocator);
        } else {
            std.mem.writeInt(i32, buf.items[primary_output_offset_slot..][0..4], -1, .little);
        }

        // benchRequirement (if present)
        if (self.bench_requirement) |reqs| {
            const offset: i32 = @intCast(buf.items.len - var_block_start);
            std.mem.writeInt(i32, buf.items[bench_req_offset_slot..][0..4], offset, .little);

            var vi_buf: [5]u8 = undefined;
            const vi_len = writeVarIntBuf(&vi_buf, @intCast(reqs.len));
            try buf.appendSlice(allocator, vi_buf[0..vi_len]);

            for (reqs) |req| {
                try req.serialize(&buf, allocator);
            }
        } else {
            std.mem.writeInt(i32, buf.items[bench_req_offset_slot..][0..4], -1, .little);
        }

        return buf.toOwnedSlice(allocator);
    }
};

fn writeVarIntBuf(buf: *[5]u8, value: i32) usize {
    var v: u32 = @bitCast(value);
    var i: usize = 0;
    while (v >= 0x80) {
        buf[i] = @truncate((v & 0x7F) | 0x80);
        v >>= 7;
        i += 1;
    }
    buf[i] = @truncate(v);
    return i + 1;
}

test "CraftingRecipeAsset serialize minimal" {
    const allocator = std.testing.allocator;

    var asset = CraftingRecipeAsset{};
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed block = 30 bytes (no variable data)
    try std.testing.expectEqual(@as(usize, 30), data.len);

    // Check nullBits is 0
    try std.testing.expectEqual(@as(u8, 0), data[0]);

    // Check all offsets are -1
    const id_offset = std.mem.readInt(i32, data[10..14], .little);
    try std.testing.expectEqual(@as(i32, -1), id_offset);
}

test "CraftingRecipeAsset serialize with id" {
    const allocator = std.testing.allocator;

    var asset = CraftingRecipeAsset{
        .id = "wooden_sword",
        .time_seconds = 5.0,
    };
    const data = try asset.serialize(allocator);
    defer allocator.free(data);

    // Fixed (30) + VarInt(12) + "wooden_sword"
    try std.testing.expectEqual(@as(usize, 30 + 1 + 12), data.len);

    // Check nullBits has id set
    try std.testing.expectEqual(@as(u8, 0x01), data[0]);

    // Check id offset is 0
    const id_offset = std.mem.readInt(i32, data[10..14], .little);
    try std.testing.expectEqual(@as(i32, 0), id_offset);
}
