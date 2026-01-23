const std = @import("std");

const log = std.log.scoped(.oauth);

/// OAuth 2.0 Device Authorization Flow
/// Used to authenticate users via Hytale's authentication service
/// The user visits a URL and enters a code, then the server polls for completion

/// Default OAuth endpoints (can be overridden via environment variables)
pub const DEFAULT_DEVICE_AUTH_URL = "https://auth.hytale.com/oauth/device/code";
pub const DEFAULT_TOKEN_URL = "https://auth.hytale.com/oauth/token";
pub const DEFAULT_SESSION_URL = "https://session.hytale.com/session";

/// Environment variable names for OAuth endpoint configuration
pub const ENV_DEVICE_AUTH_URL = "HYTALE_AUTH_DEVICE_URL";
pub const ENV_TOKEN_URL = "HYTALE_AUTH_TOKEN_URL";
pub const ENV_SESSION_URL = "HYTALE_SESSION_URL";

/// OAuth endpoints - reads from environment variables with fallback to defaults
pub const OAuthEndpoints = struct {
    /// Device authorization endpoint - returns device_code and user_code
    device_authorization: []const u8 = DEFAULT_DEVICE_AUTH_URL,
    /// Token endpoint - exchange device_code for access_token
    token: []const u8 = DEFAULT_TOKEN_URL,
    /// Session service endpoint - create game session
    session: []const u8 = DEFAULT_SESSION_URL,

    // Track if endpoints were allocated (need to be freed)
    device_authorization_owned: bool = false,
    token_owned: bool = false,
    session_owned: bool = false,

    /// Initialize endpoints from environment variables with fallback to defaults
    pub fn fromEnvironment(allocator: std.mem.Allocator) OAuthEndpoints {
        var endpoints = OAuthEndpoints{};
        const Environ = std.process.Environ;

        // Device authorization URL
        if (Environ.getWindows(.{ .block = {} }, std.unicode.wtf8ToWtf16LeStringLiteral(ENV_DEVICE_AUTH_URL))) |value_w| {
            if (std.unicode.wtf16LeToWtf8Alloc(allocator, value_w)) |url| {
                endpoints.device_authorization = url;
                endpoints.device_authorization_owned = true;
                log.info("Using device auth URL from {s}: {s}", .{ ENV_DEVICE_AUTH_URL, url });
            } else |_| {}
        }

        // Token URL
        if (Environ.getWindows(.{ .block = {} }, std.unicode.wtf8ToWtf16LeStringLiteral(ENV_TOKEN_URL))) |value_w| {
            if (std.unicode.wtf16LeToWtf8Alloc(allocator, value_w)) |url| {
                endpoints.token = url;
                endpoints.token_owned = true;
                log.info("Using token URL from {s}: {s}", .{ ENV_TOKEN_URL, url });
            } else |_| {}
        }

        // Session URL
        if (Environ.getWindows(.{ .block = {} }, std.unicode.wtf8ToWtf16LeStringLiteral(ENV_SESSION_URL))) |value_w| {
            if (std.unicode.wtf16LeToWtf8Alloc(allocator, value_w)) |url| {
                endpoints.session = url;
                endpoints.session_owned = true;
                log.info("Using session URL from {s}: {s}", .{ ENV_SESSION_URL, url });
            } else |_| {}
        }

        return endpoints;
    }

    /// Free any allocated endpoint strings
    pub fn deinit(self: *OAuthEndpoints, allocator: std.mem.Allocator) void {
        if (self.device_authorization_owned) {
            allocator.free(self.device_authorization);
            self.device_authorization = DEFAULT_DEVICE_AUTH_URL;
            self.device_authorization_owned = false;
        }
        if (self.token_owned) {
            allocator.free(self.token);
            self.token = DEFAULT_TOKEN_URL;
            self.token_owned = false;
        }
        if (self.session_owned) {
            allocator.free(self.session);
            self.session = DEFAULT_SESSION_URL;
            self.session_owned = false;
        }
    }
};

/// Device authorization response from OAuth server
pub const DeviceAuthorizationResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    verification_uri_complete: []const u8,
    expires_in: u32,
    interval: u32,
};

/// Token response from OAuth server
pub const TokenResponse = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: u32,
    refresh_token: ?[]const u8,
    scope: ?[]const u8,
};

/// OAuth error codes
pub const OAuthError = error{
    /// Still waiting for user to authorize
    AuthorizationPending,
    /// User took too long
    ExpiredToken,
    /// User denied access
    AccessDenied,
    /// Polling too fast
    SlowDown,
    /// Invalid request
    InvalidRequest,
    /// Network error
    NetworkError,
    /// Parse error
    ParseError,
};

/// OAuth client for device flow authentication
pub const OAuthClient = struct {
    allocator: std.mem.Allocator,
    endpoints: OAuthEndpoints,
    client_id: []const u8,
    client_secret: ?[]const u8,

    // Current auth state
    device_code: ?[]const u8,
    user_code: ?[]const u8,
    verification_uri: ?[]const u8,
    poll_interval: u32,
    expires_at: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, client_secret: ?[]const u8) Self {
        return .{
            .allocator = allocator,
            .endpoints = OAuthEndpoints.fromEnvironment(allocator),
            .client_id = client_id,
            .client_secret = client_secret,
            .device_code = null,
            .user_code = null,
            .verification_uri = null,
            .poll_interval = 5,
            .expires_at = 0,
        };
    }

    /// Initialize with explicit endpoints (useful for testing)
    pub fn initWithEndpoints(allocator: std.mem.Allocator, client_id: []const u8, client_secret: ?[]const u8, endpoints: OAuthEndpoints) Self {
        return .{
            .allocator = allocator,
            .endpoints = endpoints,
            .client_id = client_id,
            .client_secret = client_secret,
            .device_code = null,
            .user_code = null,
            .verification_uri = null,
            .poll_interval = 5,
            .expires_at = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.device_code) |code| self.allocator.free(code);
        if (self.user_code) |code| self.allocator.free(code);
        if (self.verification_uri) |uri| self.allocator.free(uri);
        self.endpoints.deinit(self.allocator);
    }

    /// Start the device authorization flow
    /// Returns the user code and verification URI for the user to visit
    pub fn startDeviceAuthorization(self: *Self) !struct { user_code: []const u8, verification_uri: []const u8 } {
        // In a real implementation, this would make an HTTP request to the
        // device authorization endpoint. For now, we simulate the response.

        log.info("Starting device authorization...", .{});

        // Simulated response (replace with actual HTTP request)
        const device_code = try self.allocator.dupe(u8, "SIMULATED_DEVICE_CODE");
        const user_code = try self.allocator.dupe(u8, "ABCD-1234");
        const verification_uri = try self.allocator.dupe(u8, "https://auth.hytale.com/device");

        // Store state
        if (self.device_code) |old| self.allocator.free(old);
        if (self.user_code) |old| self.allocator.free(old);
        if (self.verification_uri) |old| self.allocator.free(old);

        self.device_code = device_code;
        self.user_code = user_code;
        self.verification_uri = verification_uri;
        self.poll_interval = 5;
        self.expires_at = std.time.timestamp() + 600; // 10 minutes

        log.info("Device authorization started", .{});
        log.info("  User code: {s}", .{user_code});
        log.info("  Visit: {s}", .{verification_uri});

        return .{
            .user_code = user_code,
            .verification_uri = verification_uri,
        };
    }

    /// Poll for token (call this repeatedly until success or error)
    pub fn pollForToken(self: *Self) OAuthError!TokenResponse {
        if (self.device_code == null) {
            return OAuthError.InvalidRequest;
        }

        // Check expiration
        if (std.time.timestamp() > self.expires_at) {
            return OAuthError.ExpiredToken;
        }

        // In real implementation, make HTTP POST to token endpoint with:
        // grant_type=urn:ietf:params:oauth:grant-type:device_code
        // device_code=self.device_code
        // client_id=self.client_id

        log.debug("Polling for token...", .{});

        // Simulated - in real implementation, parse response
        // For now, always return pending (real implementation would parse JSON response)
        return OAuthError.AuthorizationPending;
    }

    /// Exchange authorization code for token
    pub fn exchangeCodeForToken(self: *Self, code: []const u8) !TokenResponse {
        _ = self;

        // In real implementation, make HTTP POST to token endpoint
        log.info("Exchanging code for token...", .{});

        // Simulated successful response
        return TokenResponse{
            .access_token = code, // Would be actual token from server
            .token_type = "Bearer",
            .expires_in = 3600,
            .refresh_token = null,
            .scope = null,
        };
    }

    /// Get poll interval in seconds
    pub fn getPollInterval(self: *const Self) u32 {
        return self.poll_interval;
    }

    /// Check if authorization is still valid (not expired)
    pub fn isValid(self: *const Self) bool {
        return self.device_code != null and std.time.timestamp() < self.expires_at;
    }
};

/// HTTP utilities for OAuth (placeholder for real implementation)
pub const HttpClient = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Make a POST request with form data
    pub fn post(self: *Self, url: []const u8, data: []const u8) ![]const u8 {
        _ = self;
        _ = url;
        _ = data;

        // This would use std.http.Client in a real implementation
        // For now, return empty response
        return "";
    }

    /// Make a GET request
    pub fn get(self: *Self, url: []const u8) ![]const u8 {
        _ = self;
        _ = url;
        return "";
    }
};

test "oauth client init" {
    const allocator = std.testing.allocator;

    // Use explicit endpoints to avoid environment variable interference
    var client = OAuthClient.initWithEndpoints(allocator, "test-client-id", null, .{});
    defer client.deinit();

    try std.testing.expect(client.device_code == null);
    try std.testing.expect(!client.isValid());
}

test "device authorization" {
    const allocator = std.testing.allocator;

    // Use explicit endpoints to avoid environment variable interference
    var client = OAuthClient.initWithEndpoints(allocator, "test-client-id", null, .{});
    defer client.deinit();

    const result = try client.startDeviceAuthorization();
    try std.testing.expect(result.user_code.len > 0);
    try std.testing.expect(result.verification_uri.len > 0);
    try std.testing.expect(client.isValid());
}

test "oauth endpoints from environment" {
    const allocator = std.testing.allocator;

    // Test default endpoints (no env vars set in test context)
    var endpoints = OAuthEndpoints.fromEnvironment(allocator);
    defer endpoints.deinit(allocator);

    // Should have default values
    try std.testing.expectEqualStrings(DEFAULT_DEVICE_AUTH_URL, endpoints.device_authorization);
    try std.testing.expectEqualStrings(DEFAULT_TOKEN_URL, endpoints.token);
    try std.testing.expectEqualStrings(DEFAULT_SESSION_URL, endpoints.session);
}
