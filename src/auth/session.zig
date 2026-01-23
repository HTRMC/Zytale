const std = @import("std");

const log = std.log.scoped(.session);

/// Get current Unix timestamp (seconds since 1970) using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io) catch return 0;
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Get random bytes using std.Io
fn getRandomBytes(buf: []u8) void {
    const io = std.Io.Threaded.global_single_threaded.io();
    io.random(buf);
}

/// Game session created after OAuth authentication
/// Contains information needed to validate client connections
pub const GameSession = struct {
    /// Session ID (UUID)
    session_id: [16]u8,

    /// Player UUID
    player_uuid: [16]u8,

    /// Player username
    username: []const u8,

    /// Access token for API calls
    access_token: []const u8,

    /// Session expiration timestamp
    expires_at: i64,

    /// Server certificate fingerprint (SHA-256)
    /// Client verifies this matches the TLS certificate
    cert_fingerprint: [32]u8,

    const Self = @This();

    pub fn isExpired(self: *const Self) bool {
        return getTimestamp() > self.expires_at;
    }
};

/// Session service client
/// Handles communication with Hytale's session service
pub const SessionService = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,

    /// Currently active session
    current_session: ?GameSession,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .endpoint = "https://session.hytale.com/session",
            .current_session = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_session) |session| {
            self.allocator.free(session.username);
            self.allocator.free(session.access_token);
        }
    }

    /// Create a new game session using the OAuth access token
    pub fn createSession(
        self: *Self,
        access_token: []const u8,
        server_cert_fingerprint: [32]u8,
    ) !*GameSession {
        log.info("Creating game session...", .{});

        // In real implementation, POST to session service with:
        // - access_token (Bearer auth header)
        // - server_address
        // - server_cert_fingerprint
        // Response contains session_id, player info, etc.

        // Simulated session creation
        const session = GameSession{
            .session_id = generateUuid(),
            .player_uuid = generateUuid(),
            .username = try self.allocator.dupe(u8, "TestPlayer"),
            .access_token = try self.allocator.dupe(u8, access_token),
            .expires_at = getTimestamp() + 86400, // 24 hours
            .cert_fingerprint = server_cert_fingerprint,
        };

        // Free old session if exists
        if (self.current_session) |old| {
            self.allocator.free(old.username);
            self.allocator.free(old.access_token);
        }

        self.current_session = session;

        log.info("Session created for player: {s}", .{session.username});

        return &self.current_session.?;
    }

    /// Verify a client's auth token matches our session
    pub fn verifyClientAuth(self: *const Self, auth_token: []const u8) bool {
        const session = self.current_session orelse return false;

        if (session.isExpired()) {
            log.warn("Session expired", .{});
            return false;
        }

        // In real implementation, verify token with session service
        // For now, simple token comparison
        return std.mem.eql(u8, session.access_token, auth_token);
    }

    /// Get current session
    pub fn getSession(self: *const Self) ?*const GameSession {
        if (self.current_session) |*session| {
            return session;
        }
        return null;
    }

    /// Invalidate current session
    pub fn invalidateSession(self: *Self) void {
        if (self.current_session) |session| {
            log.info("Invalidating session for: {s}", .{session.username});
            self.allocator.free(session.username);
            self.allocator.free(session.access_token);
            self.current_session = null;
        }
    }
};

/// Generate a random UUID v4
fn generateUuid() [16]u8 {
    var uuid: [16]u8 = undefined;
    getRandomBytes(&uuid);

    // Set version (4) and variant (2) bits per RFC 4122
    uuid[6] = (uuid[6] & 0x0F) | 0x40;
    uuid[8] = (uuid[8] & 0x3F) | 0x80;

    return uuid;
}

/// Format UUID as string
pub fn uuidToString(uuid: [16]u8) [36]u8 {
    const hex = "0123456789abcdef";
    var result: [36]u8 = undefined;
    var idx: usize = 0;

    for (0..16) |i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            result[idx] = '-';
            idx += 1;
        }
        result[idx] = hex[uuid[i] >> 4];
        idx += 1;
        result[idx] = hex[uuid[i] & 0x0F];
        idx += 1;
    }

    return result;
}

test "session service init" {
    const allocator = std.testing.allocator;

    var service = SessionService.init(allocator);
    defer service.deinit();

    try std.testing.expect(service.current_session == null);
}

test "session creation" {
    const allocator = std.testing.allocator;

    var service = SessionService.init(allocator);
    defer service.deinit();

    const fingerprint = [_]u8{0} ** 32;
    const session = try service.createSession("test-token", fingerprint);

    try std.testing.expect(!session.isExpired());
    try std.testing.expect(service.verifyClientAuth("test-token"));
    try std.testing.expect(!service.verifyClientAuth("wrong-token"));
}

test "uuid generation" {
    const uuid1 = generateUuid();
    const uuid2 = generateUuid();

    // UUIDs should be different
    try std.testing.expect(!std.mem.eql(u8, &uuid1, &uuid2));

    // Check version byte (should be 4)
    try std.testing.expectEqual(@as(u8, 0x40), uuid1[6] & 0xF0);
}
