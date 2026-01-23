const std = @import("std");

const log = std.log.scoped(.oauth);

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io) catch return 0;
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// OAuth 2.0 Device Authorization Flow
/// Used to authenticate users via Hytale's authentication service
/// The user visits a URL and enters a code, then the server polls for completion

/// Default OAuth endpoints (from Java source)
pub const DEFAULT_DEVICE_AUTH_URL = "https://oauth.accounts.hytale.com/oauth2/device/auth";
pub const DEFAULT_TOKEN_URL = "https://oauth.accounts.hytale.com/oauth2/token";

/// Environment variable names for OAuth endpoint configuration
pub const ENV_DEVICE_AUTH_URL = "HYTALE_AUTH_DEVICE_URL";
pub const ENV_TOKEN_URL = "HYTALE_AUTH_TOKEN_URL";

/// Default OAuth client ID for Hytale servers
pub const DEFAULT_CLIENT_ID = "hytale-server";

/// Default OAuth scopes
pub const DEFAULT_SCOPE = "openid+offline+auth:server";

/// OAuth endpoints - reads from environment variables with fallback to defaults
pub const OAuthEndpoints = struct {
    /// Device authorization endpoint - returns device_code and user_code
    device_authorization: []const u8 = DEFAULT_DEVICE_AUTH_URL,
    /// Token endpoint - exchange device_code for access_token
    token: []const u8 = DEFAULT_TOKEN_URL,

    // Track if endpoints were allocated (need to be freed)
    device_authorization_owned: bool = false,
    token_owned: bool = false,

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
    }
};

/// Device authorization response from OAuth server
pub const DeviceAuthorizationResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    expires_in: u32,
    interval: u32,
};

/// Token response from OAuth server
pub const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8,
    id_token: ?[]const u8,
    token_type: []const u8,
    expires_in: u32,
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
    /// Out of memory
    OutOfMemory,
    /// Invalid grant
    InvalidGrant,
};

/// OAuth client for device flow authentication
pub const OAuthClient = struct {
    allocator: std.mem.Allocator,
    endpoints: OAuthEndpoints,
    client_id: []const u8,
    scope: []const u8,

    // Current auth state
    device_code: ?[]const u8,
    user_code: ?[]const u8,
    verification_uri: ?[]const u8,
    poll_interval: u32,
    expires_at: i64,

    // Token storage (owned, need to be freed)
    access_token: ?[]const u8,
    refresh_token: ?[]const u8,
    id_token: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, scope: ?[]const u8) Self {
        return .{
            .allocator = allocator,
            .endpoints = OAuthEndpoints.fromEnvironment(allocator),
            .client_id = client_id,
            .scope = scope orelse DEFAULT_SCOPE,
            .device_code = null,
            .user_code = null,
            .verification_uri = null,
            .poll_interval = 5,
            .expires_at = 0,
            .access_token = null,
            .refresh_token = null,
            .id_token = null,
        };
    }

    /// Initialize with explicit endpoints (useful for testing)
    pub fn initWithEndpoints(allocator: std.mem.Allocator, client_id: []const u8, scope: ?[]const u8, endpoints: OAuthEndpoints) Self {
        return .{
            .allocator = allocator,
            .endpoints = endpoints,
            .client_id = client_id,
            .scope = scope orelse DEFAULT_SCOPE,
            .device_code = null,
            .user_code = null,
            .verification_uri = null,
            .poll_interval = 5,
            .expires_at = 0,
            .access_token = null,
            .refresh_token = null,
            .id_token = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.device_code) |code| self.allocator.free(code);
        if (self.user_code) |code| self.allocator.free(code);
        if (self.verification_uri) |uri| self.allocator.free(uri);
        if (self.access_token) |token| self.allocator.free(token);
        if (self.refresh_token) |token| self.allocator.free(token);
        if (self.id_token) |token| self.allocator.free(token);
        self.endpoints.deinit(self.allocator);
    }

    /// Start the device authorization flow
    /// POST https://oauth.accounts.hytale.com/oauth2/device/auth
    /// Body: client_id=hytale-server&scope=openid+offline+auth:server
    /// Returns the user code and verification URI for the user to visit
    pub fn startDeviceAuthorization(self: *Self) OAuthError!struct { user_code: []const u8, verification_uri: []const u8 } {
        log.info("Starting device authorization...", .{});
        log.debug("  Endpoint: {s}", .{self.endpoints.device_authorization});

        // Build form-urlencoded body
        const body = std.fmt.allocPrint(self.allocator, "client_id={s}&scope={s}", .{
            self.client_id,
            self.scope,
        }) catch return OAuthError.OutOfMemory;
        defer self.allocator.free(body);

        // Make HTTP request
        const response = self.makePostRequest(
            self.endpoints.device_authorization,
            body,
            "application/x-www-form-urlencoded",
            null,
        ) catch |err| {
            log.err("Failed to start device authorization: {}", .{err});
            return OAuthError.NetworkError;
        };
        defer self.allocator.free(response);

        // Parse JSON response
        const parsed = std.json.parseFromSlice(struct {
            device_code: []const u8,
            user_code: []const u8,
            verification_uri: []const u8,
            verification_uri_complete: ?[]const u8 = null,
            expires_in: u32,
            interval: u32,
        }, self.allocator, response, .{}) catch {
            log.err("Failed to parse device authorization response: {s}", .{response});
            return OAuthError.ParseError;
        };
        defer parsed.deinit();

        // Store state (duplicate strings since parsed will be freed)
        if (self.device_code) |old| self.allocator.free(old);
        if (self.user_code) |old| self.allocator.free(old);
        if (self.verification_uri) |old| self.allocator.free(old);

        self.device_code = self.allocator.dupe(u8, parsed.value.device_code) catch return OAuthError.OutOfMemory;
        self.user_code = self.allocator.dupe(u8, parsed.value.user_code) catch return OAuthError.OutOfMemory;
        self.verification_uri = self.allocator.dupe(u8, parsed.value.verification_uri) catch return OAuthError.OutOfMemory;
        self.poll_interval = parsed.value.interval;
        self.expires_at = getTimestamp() + @as(i64, parsed.value.expires_in);

        log.info("Device authorization started", .{});
        log.info("  User code: {s}", .{self.user_code.?});
        log.info("  Visit: {s}", .{self.verification_uri.?});
        log.info("  Expires in: {d} seconds", .{parsed.value.expires_in});

        return .{
            .user_code = self.user_code.?,
            .verification_uri = self.verification_uri.?,
        };
    }

    /// Poll for token (call this repeatedly until success or error)
    /// POST https://oauth.accounts.hytale.com/oauth2/token
    /// Body: grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=<code>&client_id=hytale-server
    pub fn pollForToken(self: *Self) OAuthError!TokenResponse {
        if (self.device_code == null) {
            return OAuthError.InvalidRequest;
        }

        // Check expiration
        if (getTimestamp() > self.expires_at) {
            return OAuthError.ExpiredToken;
        }

        log.debug("Polling for token...", .{});

        // Build form-urlencoded body
        const body = std.fmt.allocPrint(
            self.allocator,
            "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code={s}&client_id={s}",
            .{ self.device_code.?, self.client_id },
        ) catch return OAuthError.OutOfMemory;
        defer self.allocator.free(body);

        // Make HTTP request
        const response = self.makePostRequest(
            self.endpoints.token,
            body,
            "application/x-www-form-urlencoded",
            null,
        ) catch |err| {
            log.err("Token poll request failed: {}", .{err});
            return OAuthError.NetworkError;
        };
        defer self.allocator.free(response);

        // Check for error response first
        if (std.json.parseFromSlice(struct {
            @"error": []const u8,
            error_description: ?[]const u8 = null,
        }, self.allocator, response, .{})) |error_parsed| {
            defer error_parsed.deinit();
            const error_code = error_parsed.value.@"error";

            if (std.mem.eql(u8, error_code, "authorization_pending")) {
                return OAuthError.AuthorizationPending;
            } else if (std.mem.eql(u8, error_code, "slow_down")) {
                self.poll_interval += 5; // Increase interval
                return OAuthError.SlowDown;
            } else if (std.mem.eql(u8, error_code, "expired_token")) {
                return OAuthError.ExpiredToken;
            } else if (std.mem.eql(u8, error_code, "access_denied")) {
                return OAuthError.AccessDenied;
            } else {
                log.err("OAuth error: {s}", .{error_code});
                if (error_parsed.value.error_description) |desc| {
                    log.err("  Description: {s}", .{desc});
                }
                return OAuthError.InvalidRequest;
            }
        } else |_| {
            // Not an error response, try parsing as token response
        }

        // Parse successful token response
        const parsed = std.json.parseFromSlice(struct {
            access_token: []const u8,
            refresh_token: ?[]const u8 = null,
            id_token: ?[]const u8 = null,
            token_type: []const u8 = "Bearer",
            expires_in: u32 = 3600,
            scope: ?[]const u8 = null,
        }, self.allocator, response, .{}) catch {
            log.err("Failed to parse token response: {s}", .{response});
            return OAuthError.ParseError;
        };
        defer parsed.deinit();

        // Store tokens (duplicate since parsed will be freed)
        if (self.access_token) |old| self.allocator.free(old);
        if (self.refresh_token) |old| self.allocator.free(old);
        if (self.id_token) |old| self.allocator.free(old);

        self.access_token = self.allocator.dupe(u8, parsed.value.access_token) catch return OAuthError.OutOfMemory;
        if (parsed.value.refresh_token) |rt| {
            self.refresh_token = self.allocator.dupe(u8, rt) catch return OAuthError.OutOfMemory;
        } else {
            self.refresh_token = null;
        }
        if (parsed.value.id_token) |it| {
            self.id_token = self.allocator.dupe(u8, it) catch return OAuthError.OutOfMemory;
        } else {
            self.id_token = null;
        }

        log.info("Token received successfully!", .{});

        return TokenResponse{
            .access_token = self.access_token.?,
            .refresh_token = self.refresh_token,
            .id_token = self.id_token,
            .token_type = "Bearer",
            .expires_in = parsed.value.expires_in,
            .scope = null,
        };
    }

    /// Refresh an expired access token
    /// POST https://oauth.accounts.hytale.com/oauth2/token
    /// Body: grant_type=refresh_token&client_id=hytale-server&refresh_token=<token>
    pub fn refreshToken(self: *Self, refresh_token: []const u8) OAuthError!TokenResponse {
        log.info("Refreshing access token...", .{});

        // Build form-urlencoded body
        const body = std.fmt.allocPrint(
            self.allocator,
            "grant_type=refresh_token&client_id={s}&refresh_token={s}",
            .{ self.client_id, refresh_token },
        ) catch return OAuthError.OutOfMemory;
        defer self.allocator.free(body);

        // Make HTTP request
        const response = self.makePostRequest(
            self.endpoints.token,
            body,
            "application/x-www-form-urlencoded",
            null,
        ) catch |err| {
            log.err("Token refresh request failed: {}", .{err});
            return OAuthError.NetworkError;
        };
        defer self.allocator.free(response);

        // Check for error response
        if (std.json.parseFromSlice(struct {
            @"error": []const u8,
            error_description: ?[]const u8 = null,
        }, self.allocator, response, .{})) |error_parsed| {
            defer error_parsed.deinit();
            const error_code = error_parsed.value.@"error";

            if (std.mem.eql(u8, error_code, "invalid_grant")) {
                return OAuthError.InvalidGrant;
            } else {
                log.err("Token refresh error: {s}", .{error_code});
                return OAuthError.InvalidRequest;
            }
        } else |_| {}

        // Parse successful token response
        const parsed = std.json.parseFromSlice(struct {
            access_token: []const u8,
            refresh_token: ?[]const u8 = null,
            id_token: ?[]const u8 = null,
            token_type: []const u8 = "Bearer",
            expires_in: u32 = 3600,
            scope: ?[]const u8 = null,
        }, self.allocator, response, .{}) catch {
            log.err("Failed to parse refresh token response: {s}", .{response});
            return OAuthError.ParseError;
        };
        defer parsed.deinit();

        // Store tokens
        if (self.access_token) |old| self.allocator.free(old);
        if (self.refresh_token) |old| self.allocator.free(old);
        if (self.id_token) |old| self.allocator.free(old);

        self.access_token = self.allocator.dupe(u8, parsed.value.access_token) catch return OAuthError.OutOfMemory;
        if (parsed.value.refresh_token) |rt| {
            self.refresh_token = self.allocator.dupe(u8, rt) catch return OAuthError.OutOfMemory;
        } else {
            // Keep the old refresh token if a new one wasn't provided
            self.refresh_token = self.allocator.dupe(u8, refresh_token) catch return OAuthError.OutOfMemory;
        }
        if (parsed.value.id_token) |it| {
            self.id_token = self.allocator.dupe(u8, it) catch return OAuthError.OutOfMemory;
        } else {
            self.id_token = null;
        }

        log.info("Token refreshed successfully!", .{});

        return TokenResponse{
            .access_token = self.access_token.?,
            .refresh_token = self.refresh_token,
            .id_token = self.id_token,
            .token_type = "Bearer",
            .expires_in = parsed.value.expires_in,
            .scope = null,
        };
    }

    /// Make a POST request to the given URL
    fn makePostRequest(
        self: *Self,
        url: []const u8,
        body: []const u8,
        content_type: []const u8,
        bearer_token: ?[]const u8,
    ) ![]u8 {
        log.debug("POST {s}", .{url});
        log.debug("Body: {s}", .{body});

        // Get I/O handle for async operations
        const io = std.Io.Threaded.global_single_threaded.io();

        // Create HTTP client
        var client = std.http.Client{
            .allocator = self.allocator,
            .io = io,
        };
        defer client.deinit();

        // Build headers
        var headers_list = std.ArrayListUnmanaged(std.http.Header){};
        defer headers_list.deinit(self.allocator);

        try headers_list.append(self.allocator, .{ .name = "Content-Type", .value = content_type });

        if (bearer_token) |token| {
            const auth_value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
            defer self.allocator.free(auth_value);
            try headers_list.append(self.allocator, .{ .name = "Authorization", .value = auth_value });
        }

        // Create an allocating writer for the response body
        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_writer.deinit();

        // Perform the fetch request
        const result = client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body,
            .extra_headers = headers_list.items,
            .response_writer = &response_writer.writer,
        }) catch |err| {
            log.err("HTTP request failed: {}", .{err});
            return error.NetworkError;
        };

        // Check status code
        if (result.status != .ok and result.status != .bad_request) {
            log.err("OAuth request failed with status: {}", .{result.status});
            response_writer.deinit();
            return error.RequestFailed;
        }

        // Get the response body
        var array_list = response_writer.toArrayList();
        const response_body = array_list.toOwnedSlice(self.allocator) catch {
            array_list.deinit(self.allocator);
            return error.OutOfMemory;
        };

        log.debug("Response ({d} bytes): {s}", .{ response_body.len, response_body });
        return response_body;
    }

    /// Get poll interval in seconds
    pub fn getPollInterval(self: *const Self) u32 {
        return self.poll_interval;
    }

    /// Check if authorization is still valid (not expired)
    pub fn isValid(self: *const Self) bool {
        return self.device_code != null and getTimestamp() < self.expires_at;
    }

    /// Get the current access token (if available)
    pub fn getAccessToken(self: *const Self) ?[]const u8 {
        return self.access_token;
    }

    /// Get the current refresh token (if available)
    pub fn getRefreshToken(self: *const Self) ?[]const u8 {
        return self.refresh_token;
    }

    /// Get the current ID token (if available)
    pub fn getIdToken(self: *const Self) ?[]const u8 {
        return self.id_token;
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

test "oauth endpoints from environment" {
    const allocator = std.testing.allocator;

    // Test default endpoints (no env vars set in test context)
    var endpoints = OAuthEndpoints.fromEnvironment(allocator);
    defer endpoints.deinit(allocator);

    // Should have default values
    try std.testing.expectEqualStrings(DEFAULT_DEVICE_AUTH_URL, endpoints.device_authorization);
    try std.testing.expectEqualStrings(DEFAULT_TOKEN_URL, endpoints.token);
}
