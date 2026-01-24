/// TagPattern Asset Type
///
/// Represents a tag matching pattern for game logic.
/// Supports recursive patterns: Equals, And, Or, Not.
///
/// JSON format:
/// - { "Op": "Equals", "Tag": "Type=Soil" }
/// - { "Op": "Or", "Patterns": [{ "Op": "Equals", "Tag": "Bush" }, ...] }
/// - { "Op": "Not", "Pattern": { "Op": "Equals", "Tag": "Water" } }

const std = @import("std");
const json = @import("../json.zig");
const Allocator = std.mem.Allocator;

/// Tag pattern operation type
pub const TagPatternType = enum(u8) {
    equals = 0,
    @"and" = 1,
    @"or" = 2,
    not = 3,

    pub fn fromString(s: []const u8) ?TagPatternType {
        if (std.mem.eql(u8, s, "Equals")) return .equals;
        if (std.mem.eql(u8, s, "And")) return .@"and";
        if (std.mem.eql(u8, s, "Or")) return .@"or";
        if (std.mem.eql(u8, s, "Not")) return .not;
        return null;
    }
};

/// TagPattern asset - recursive structure
pub const TagPatternAsset = struct {
    /// Asset ID (derived from filename, only set for root patterns)
    id: []const u8,

    /// Pattern operation type
    type: TagPatternType,

    /// Tag name (for Equals type)
    tag: ?[]const u8,

    /// Tag index (resolved during loading, -1 if unresolved)
    tag_index: i32,

    /// Child patterns (for And/Or types)
    operands: ?[]TagPatternAsset,

    /// Single child pattern (for Not type)
    not_pattern: ?*TagPatternAsset,

    const Self = @This();

    /// Maximum recursion depth for parsing
    const MAX_DEPTH: usize = 10;

    /// Parse from JSON content (top-level entry point)
    pub fn parseJson(allocator: Allocator, id: []const u8, content: []const u8) !Self {
        var parsed = try json.parseJson(allocator, content);
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidJson;
        }

        var result = try parsePattern(allocator, parsed.value.object, 0);
        result.id = try allocator.dupe(u8, id);
        return result;
    }

    /// Parse a pattern object (recursive)
    fn parsePattern(allocator: Allocator, obj: std.json.ObjectMap, depth: usize) !Self {
        if (depth > MAX_DEPTH) {
            return error.MaxDepthExceeded;
        }

        // Get operation type
        const op_str = json.getStringField(obj, "Op") orelse return error.MissingOp;
        const pattern_type = TagPatternType.fromString(op_str) orelse return error.InvalidOp;

        var result = Self{
            .id = "",
            .type = pattern_type,
            .tag = null,
            .tag_index = -1,
            .operands = null,
            .not_pattern = null,
        };

        switch (pattern_type) {
            .equals => {
                // Equals: get Tag field
                const tag = json.getStringField(obj, "Tag") orelse return error.MissingTag;
                result.tag = try allocator.dupe(u8, tag);
            },
            .@"and", .@"or" => {
                // And/Or: get Patterns array
                const patterns_arr = json.getArrayField(obj, "Patterns") orelse return error.MissingPatterns;

                var operands = try allocator.alloc(TagPatternAsset, patterns_arr.items.len);
                errdefer allocator.free(operands);

                for (patterns_arr.items, 0..) |item, i| {
                    if (item != .object) {
                        return error.InvalidPattern;
                    }
                    operands[i] = try parsePattern(allocator, item.object, depth + 1);
                }

                result.operands = operands;
            },
            .not => {
                // Not: get single Pattern
                const pattern_obj = json.getObjectField(obj, "Pattern") orelse return error.MissingPattern;

                const not_pattern = try allocator.create(TagPatternAsset);
                errdefer allocator.destroy(not_pattern);

                not_pattern.* = try parsePattern(allocator, pattern_obj, depth + 1);
                result.not_pattern = not_pattern;
            },
        }

        return result;
    }

    /// Free allocated memory (recursive)
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.id.len > 0) allocator.free(self.id);
        if (self.tag) |t| allocator.free(t);

        if (self.operands) |ops| {
            for (ops) |*op| {
                op.deinit(allocator);
            }
            allocator.free(ops);
        }

        if (self.not_pattern) |np| {
            np.deinit(allocator);
            allocator.destroy(np);
        }
    }

    /// Count total patterns (including nested)
    pub fn countPatterns(self: *const Self) usize {
        var count: usize = 1;

        if (self.operands) |ops| {
            for (ops) |*op| {
                count += op.countPatterns();
            }
        }

        if (self.not_pattern) |np| {
            count += np.countPatterns();
        }

        return count;
    }
};

test "TagPatternAsset parse equals" {
    const allocator = std.testing.allocator;
    const content =
        \\{
        \\  "Op": "Equals",
        \\  "Tag": "Vine"
        \\}
    ;

    var asset = try TagPatternAsset.parseJson(allocator, "Vine", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("Vine", asset.id);
    try std.testing.expectEqual(TagPatternType.equals, asset.type);
    try std.testing.expectEqualStrings("Vine", asset.tag.?);
}

test "TagPatternAsset parse or" {
    const allocator = std.testing.allocator;
    const content =
        \\{
        \\  "Op": "Or",
        \\  "Patterns": [{
        \\    "Op": "Equals",
        \\    "Tag": "Bush"
        \\  }, {
        \\    "Op": "Equals",
        \\    "Tag": "Seed"
        \\  }]
        \\}
    ;

    var asset = try TagPatternAsset.parseJson(allocator, "Bush_Or_Seed", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("Bush_Or_Seed", asset.id);
    try std.testing.expectEqual(TagPatternType.@"or", asset.type);
    try std.testing.expect(asset.operands != null);
    try std.testing.expectEqual(@as(usize, 2), asset.operands.?.len);
    try std.testing.expectEqualStrings("Bush", asset.operands.?[0].tag.?);
    try std.testing.expectEqualStrings("Seed", asset.operands.?[1].tag.?);
}
