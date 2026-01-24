/// Trail Asset Type
///
/// Represents a particle trail effect configuration.

const std = @import("std");
const json = @import("../json.zig");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;

const Color = common.Color;
const ColorAlpha = common.ColorAlpha;

/// FX render mode for visual effects
pub const FXRenderMode = enum(u8) {
    blend_linear = 0,
    blend_add = 1,
    erosion = 2,
    distortion = 3,

    pub fn fromString(s: []const u8) ?FXRenderMode {
        if (std.mem.eql(u8, s, "BlendLinear") or std.mem.eql(u8, s, "BLEND_LINEAR")) return .blend_linear;
        if (std.mem.eql(u8, s, "BlendAdd") or std.mem.eql(u8, s, "BLEND_ADD")) return .blend_add;
        if (std.mem.eql(u8, s, "Erosion") or std.mem.eql(u8, s, "EROSION")) return .erosion;
        if (std.mem.eql(u8, s, "Distortion") or std.mem.eql(u8, s, "DISTORTION")) return .distortion;
        return null;
    }
};

/// Edge data for trail start/end
pub const EdgeData = struct {
    /// Lifetime in seconds
    lifetime: f32,

    /// Size/width
    size: f32,

    /// Color with alpha
    color: ColorAlpha,

    pub const DEFAULTS = EdgeData{
        .lifetime = 1.0,
        .size = 1.0,
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
};

/// Trail asset
pub const TrailAsset = struct {
    /// Asset ID (derived from filename)
    id: []const u8,

    /// Texture path/identifier
    texture: []const u8,

    /// Trail lifespan in ticks
    life_span: i32,

    /// Roll angle in degrees
    roll: f32,

    /// Start edge configuration
    start: ?EdgeData,

    /// End edge configuration
    end: ?EdgeData,

    /// Light influence (0.0 - 1.0)
    light_influence: f32,

    /// Render mode
    render_mode: FXRenderMode,

    /// Smooth interpolation
    smooth: bool,

    /// Frame lifespan (for animated textures)
    frame_life_span: i32,

    const Self = @This();

    /// Default values
    pub const DEFAULTS = Self{
        .id = "",
        .texture = "",
        .life_span = 20,
        .roll = 0.0,
        .start = null,
        .end = null,
        .light_influence = 1.0,
        .render_mode = .blend_linear,
        .smooth = true,
        .frame_life_span = 1,
    };

    /// Parse from JSON content
    pub fn parseJson(allocator: Allocator, id: []const u8, content: []const u8) !Self {
        var parsed = try json.parseJson(allocator, content);
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidJson;
        }

        const obj = parsed.value.object;

        // Get texture (JSON uses "TexturePath" or "Texture")
        const texture_str = json.getStringField(obj, "TexturePath") orelse
            json.getStringField(obj, "Texture") orelse "";
        const texture = if (texture_str.len > 0)
            try allocator.dupe(u8, texture_str)
        else
            try allocator.dupe(u8, "");

        // Get render mode
        const render_mode_str = json.getStringField(obj, "RenderMode");
        const render_mode = if (render_mode_str) |s|
            FXRenderMode.fromString(s) orelse DEFAULTS.render_mode
        else
            DEFAULTS.render_mode;

        // Parse start edge
        const start = if (json.getObjectField(obj, "Start")) |start_obj|
            parseEdge(start_obj)
        else
            null;

        // Parse end edge
        const end = if (json.getObjectField(obj, "End")) |end_obj|
            parseEdge(end_obj)
        else
            null;

        return .{
            .id = try allocator.dupe(u8, id),
            .texture = texture,
            .life_span = json.getNumberFieldI32(obj, "LifeSpan") orelse DEFAULTS.life_span,
            .roll = json.getNumberFieldF32(obj, "Roll") orelse DEFAULTS.roll,
            .start = start,
            .end = end,
            .light_influence = json.getNumberFieldF32(obj, "LightInfluence") orelse DEFAULTS.light_influence,
            .render_mode = render_mode,
            .smooth = json.getBoolField(obj, "Smooth") orelse DEFAULTS.smooth,
            .frame_life_span = json.getNumberFieldI32(obj, "FrameLifeSpan") orelse DEFAULTS.frame_life_span,
        };
    }

    fn parseEdge(obj: std.json.ObjectMap) EdgeData {
        var edge = EdgeData.DEFAULTS;

        edge.lifetime = json.getNumberFieldF32(obj, "Lifetime") orelse EdgeData.DEFAULTS.lifetime;
        // JSON uses "Width" or "Size"
        edge.size = json.getNumberFieldF32(obj, "Width") orelse
            json.getNumberFieldF32(obj, "Size") orelse EdgeData.DEFAULTS.size;

        // Parse color if present - supports formats:
        // - "#RRGGBB" or "RRGGBB" (simple hex)
        // - "rgba(#RRGGBB, 0.5)" (RGBA with alpha as float)
        if (json.getStringField(obj, "Color")) |color_str| {
            const parsed = parseRgbaColor(color_str);
            edge.color = parsed;
        }

        return edge;
    }

    /// Parse color in formats: "#RRGGBB", "RRGGBB", or "rgba(#RRGGBB, 0.5)"
    fn parseRgbaColor(color_str: []const u8) ColorAlpha {
        // Check for rgba() format
        if (std.mem.startsWith(u8, color_str, "rgba(")) {
            // Format: "rgba(#ffffff, 0.9)"
            const inner_start = 5; // After "rgba("
            const inner_end = std.mem.indexOf(u8, color_str, ")") orelse color_str.len;
            const inner = color_str[inner_start..inner_end];

            // Find comma separator
            const comma_pos = std.mem.indexOf(u8, inner, ",") orelse inner.len;
            const hex_part = std.mem.trim(u8, inner[0..comma_pos], " ");

            // Parse hex color
            const color = Color.fromHex(hex_part) orelse Color.WHITE;

            // Parse alpha (after comma)
            var alpha: u8 = 255;
            if (comma_pos < inner.len) {
                const alpha_str = std.mem.trim(u8, inner[comma_pos + 1 ..], " ");
                const alpha_float = std.fmt.parseFloat(f32, alpha_str) catch 1.0;
                alpha = @intFromFloat(@min(255.0, @max(0.0, alpha_float * 255.0)));
            }

            return ColorAlpha.fromColor(color, alpha);
        }

        // Simple hex format
        if (Color.fromHex(color_str)) |c| {
            return ColorAlpha.fromColor(c, 255);
        }

        return EdgeData.DEFAULTS.color;
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.texture);
    }
};

test "TrailAsset parse defaults" {
    const allocator = std.testing.allocator;
    const content = "{}";

    var asset = try TrailAsset.parseJson(allocator, "test_trail", content);
    defer asset.deinit(allocator);

    try std.testing.expectEqualStrings("test_trail", asset.id);
    try std.testing.expectEqual(TrailAsset.DEFAULTS.life_span, asset.life_span);
    try std.testing.expectEqual(TrailAsset.DEFAULTS.render_mode, asset.render_mode);
}
