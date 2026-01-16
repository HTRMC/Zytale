const std = @import("std");
const oauth = @import("oauth.zig");
const session = @import("session.zig");

pub const OAuthClient = oauth.OAuthClient;
pub const SessionClient = session.SessionClient;

const log = std.log.scoped(.auth);

/// Server authentication state
pub const ServerAuth = struct {
    allocator: std.mem.Allocator,
    oauth_client: OAuthClient,
    session_client: SessionClient,

    // Tokens
    access_token: ?[]const u8 = null,
    refresh_token: ?[]const u8 = null,
    session_token: ?[]const u8 = null,
    identity_token: ?[]const u8 = null,

    // Profile
    profile_uuid: ?[36]u8 = null,
    profile_username: ?[]const u8 = null,

    // Server session ID (random UUID for this server instance)
    server_session_id: [36]u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .oauth_client = OAuthClient.init(allocator),
            .session_client = SessionClient.init(allocator),
            .server_session_id = generateUuid(),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.access_token) |t| self.allocator.free(t);
        if (self.refresh_token) |t| self.allocator.free(t);
        if (self.session_token) |t| self.allocator.free(t);
        if (self.identity_token) |t| self.allocator.free(t);
        if (self.profile_username) |u| self.allocator.free(u);
        self.oauth_client.deinit();
        self.session_client.deinit();
    }

    /// Start device authorization flow
    pub fn startDeviceFlow(self: *Self) !oauth.DeviceAuthResponse {
        return self.oauth_client.requestDeviceAuthorization();
    }

    /// Poll for device flow completion
    pub fn pollDeviceToken(self: *Self, device_code: []const u8) !?oauth.TokenResponse {
        return self.oauth_client.pollDeviceToken(device_code);
    }

    /// Set tokens from OAuth response
    pub fn setOAuthTokens(self: *Self, tokens: oauth.TokenResponse) !void {
        if (self.access_token) |t| self.allocator.free(t);
        if (self.refresh_token) |t| self.allocator.free(t);

        if (tokens.access_token) |at| {
            self.access_token = try self.allocator.dupe(u8, at);
        }
        if (tokens.refresh_token) |rt| {
            self.refresh_token = try self.allocator.dupe(u8, rt);
        }
    }

    /// Get game profiles using OAuth access token
    pub fn getGameProfiles(self: *Self) !?session.ProfilesResponse {
        const token = self.access_token orelse return error.NoAccessToken;
        return self.session_client.getGameProfiles(token);
    }

    /// Create game session for a profile
    pub fn createGameSession(self: *Self, profile_uuid: []const u8) !void {
        const token = self.access_token orelse return error.NoAccessToken;
        const response = try self.session_client.createGameSession(token, profile_uuid) orelse return error.SessionCreationFailed;

        // Store tokens
        if (self.session_token) |t| self.allocator.free(t);
        if (self.identity_token) |t| self.allocator.free(t);

        self.session_token = try self.allocator.dupe(u8, response.session_token);
        self.identity_token = try self.allocator.dupe(u8, response.identity_token);

        // Store profile UUID
        var uuid_buf: [36]u8 = undefined;
        @memcpy(&uuid_buf, profile_uuid[0..36]);
        self.profile_uuid = uuid_buf;

        log.info("Game session created successfully", .{});
    }

    /// Request auth grant for a connecting client
    pub fn requestAuthGrant(self: *Self, client_identity_token: []const u8) !?[]const u8 {
        const session_token = self.session_token orelse return error.NoSessionToken;
        return self.session_client.requestAuthGrant(
            client_identity_token,
            &self.server_session_id,
            session_token,
        );
    }

    /// Check if we have valid session tokens
    pub fn isAuthenticated(self: *Self) bool {
        return self.session_token != null and self.identity_token != null;
    }

    /// Get server identity token for AuthGrant packet
    pub fn getIdentityToken(self: *Self) ?[]const u8 {
        return self.identity_token;
    }

    /// Get session token
    pub fn getSessionToken(self: *Self) ?[]const u8 {
        return self.session_token;
    }
};

fn generateUuid() [36]u8 {
    // Generate random bytes using DefaultCsprng
    var bytes: [16]u8 = undefined;
    // Get entropy from Instant timestamp
    const instant = std.time.Instant.now() catch {
        // Fallback to a simple counter if Instant not supported
        const seed_bytes: [32]u8 = .{0} ** 32;
        var csprng = std.Random.DefaultCsprng.init(seed_bytes);
        csprng.fill(&bytes);
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        return formatUuidBytes(bytes);
    };
    var seed_bytes: [32]u8 = .{0} ** 32;
    const ts_bytes = std.mem.asBytes(&instant.timestamp);
    @memcpy(seed_bytes[0..ts_bytes.len], ts_bytes);
    var csprng = std.Random.DefaultCsprng.init(seed_bytes);
    csprng.fill(&bytes);

    // Set version 4 (random) and variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 1

    return formatUuidBytes(bytes);
}

fn formatUuidBytes(bytes: [16]u8) [36]u8 {
    var uuid: [36]u8 = undefined;
    const hex = "0123456789abcdef";
    var i: usize = 0;
    var j: usize = 0;
    while (i < 16) : (i += 1) {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            uuid[j] = '-';
            j += 1;
        }
        uuid[j] = hex[bytes[i] >> 4];
        uuid[j + 1] = hex[bytes[i] & 0x0f];
        j += 2;
    }
    return uuid;
}

test "generate uuid" {
    const uuid = generateUuid();
    std.debug.print("UUID: {s}\n", .{uuid});
    // Check format: 8-4-4-4-12
    try std.testing.expect(uuid[8] == '-');
    try std.testing.expect(uuid[13] == '-');
    try std.testing.expect(uuid[18] == '-');
    try std.testing.expect(uuid[23] == '-');
}
