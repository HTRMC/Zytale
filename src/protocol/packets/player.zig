const std = @import("std");
const varint = @import("../../net/packet/varint.zig");

/// SetClientId packet (ID=100)
/// Assigns the client a network entity ID
///
/// Format:
/// [4 bytes] client_id (u32 LE)
pub const SetClientId = struct {
    client_id: u32,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, 4);
        std.mem.writeInt(u32, buf[0..4], self.client_id, .little);
        return buf;
    }
};

/// SetGameMode packet (ID=101)
/// Sets the player's game mode
///
/// Format:
/// [1 byte] mode
///   0 = Survival
///   1 = Creative
///   2 = Adventure
///   3 = Spectator
pub const SetGameMode = struct {
    mode: GameMode,

    pub const GameMode = enum(u8) {
        survival = 0,
        creative = 1,
        adventure = 2,
        spectator = 3,
    };

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, 1);
        buf[0] = @intFromEnum(self.mode);
        return buf;
    }
};

/// ViewRadius packet (ID=32)
/// Sets the chunk loading view distance
///
/// Format:
/// [4 bytes] radius (u32 LE) - radius in chunks
pub const ViewRadius = struct {
    radius: u32,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, 4);
        std.mem.writeInt(u32, buf[0..4], self.radius, .little);
        return buf;
    }
};

/// SetEntitySeed packet (ID=160)
/// Sets the seed for entity ID generation
///
/// Format:
/// [4 bytes] seed (u32 LE)
pub const SetEntitySeed = struct {
    seed: u32,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, 4);
        std.mem.writeInt(u32, buf[0..4], self.seed, .little);
        return buf;
    }
};

/// ConnectAccept packet (ID=14)
/// Confirms successful connection/authentication
///
/// Format:
/// [1 byte] status (0 = success)
/// [optional additional data]
pub const ConnectAccept = struct {
    status: u8,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, 1);
        buf[0] = self.status;
        return buf;
    }

    pub fn success() Self {
        return Self{ .status = 0 };
    }
};

/// Pong packet (ID=3)
/// Response to Ping packet
///
/// Format:
/// [20 bytes] timestamp and echo data
pub const Pong = struct {
    data: [20]u8,

    const Self = @This();

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, 20);
        @memcpy(buf, &self.data);
        return buf;
    }

    /// Create Pong from Ping payload (echo back)
    pub fn fromPing(ping_data: []const u8) Self {
        var data: [20]u8 = [_]u8{0} ** 20;
        const copy_len = @min(ping_data.len, 20);
        @memcpy(data[0..copy_len], ping_data[0..copy_len]);
        return Self{ .data = data };
    }
};

/// UpdateMovementSettings packet (ID=110)
/// Sends movement configuration to the client
///
/// This is a complex packet with many fields. For now, we'll use a fixed default.
/// Full format is 252 bytes.
pub const UpdateMovementSettings = struct {
    const Self = @This();
    const SIZE = 252;

    /// Create default movement settings
    pub fn defaultSettings(allocator: std.mem.Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, SIZE);
        @memset(buf, 0);

        // Set some reasonable defaults
        // Walk speed
        std.mem.writeInt(f32, buf[0..4], 4.317, .little);
        // Sprint speed
        std.mem.writeInt(f32, buf[4..8], 5.612, .little);
        // Jump height
        std.mem.writeInt(f32, buf[8..12], 1.25, .little);
        // Gravity
        std.mem.writeInt(f32, buf[12..16], 32.0, .little);

        return buf;
    }
};

/// WorldSettings packet (ID=20)
/// Sends world configuration (compressed)
/// This is a complex packet that contains game rules, world configuration, etc.
pub const WorldSettings = struct {
    // This packet is typically compressed and quite large
    // For minimal implementation, we can send an empty/minimal configuration

    pub fn minimal(allocator: std.mem.Allocator) ![]u8 {
        // Minimal world settings - just version info
        // Real implementation would include all game rules
        var buf = try allocator.alloc(u8, 5);

        // Version byte
        buf[0] = 1;
        // Minimal data
        @memset(buf[1..], 0);

        return buf;
    }
};

test "set client id serialization" {
    const allocator = std.testing.allocator;

    const packet = SetClientId{ .client_id = 12345 };
    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 4), data.len);
    try std.testing.expectEqual(@as(u32, 12345), std.mem.readInt(u32, data[0..4], .little));
}

test "set game mode serialization" {
    const allocator = std.testing.allocator;

    const packet = SetGameMode{ .mode = .creative };
    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 1), data.len);
    try std.testing.expectEqual(@as(u8, 1), data[0]);
}

test "view radius serialization" {
    const allocator = std.testing.allocator;

    const packet = ViewRadius{ .radius = 8 };
    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 4), data.len);
    try std.testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, data[0..4], .little));
}

test "pong from ping" {
    const ping_data = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 };
    const pong = Pong.fromPing(&ping_data);

    // Should copy first 20 bytes
    try std.testing.expectEqualSlices(u8, ping_data[0..20], &pong.data);
}
