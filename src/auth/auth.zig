const std = @import("std");
const OAuthClient = @import("oauth.zig").OAuthClient;
const OAuthError = @import("oauth.zig").OAuthError;
const SessionService = @import("session.zig").SessionService;
const GameSession = @import("session.zig").GameSession;

const log = std.log.scoped(.auth);

/// Authentication state machine
pub const AuthState = enum {
    /// Not authenticated, waiting to start
    idle,
    /// Device authorization started, waiting for user
    awaiting_user,
    /// Polling for token
    polling,
    /// Token received, creating session
    creating_session,
    /// Fully authenticated
    authenticated,
    /// Authentication failed
    failed,
};

/// Server authentication manager
/// Orchestrates OAuth device flow and session creation
pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    oauth_client: OAuthClient,
    session_service: SessionService,
    state: AuthState,

    /// Server certificate fingerprint for session binding
    server_cert_fingerprint: [32]u8,

    /// Error message if authentication failed
    error_message: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8) Self {
        return .{
            .allocator = allocator,
            .oauth_client = OAuthClient.init(allocator, client_id, null),
            .session_service = SessionService.init(allocator),
            .state = .idle,
            .server_cert_fingerprint = [_]u8{0} ** 32,
            .error_message = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.oauth_client.deinit();
        self.session_service.deinit();
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Set server certificate fingerprint for session binding
    pub fn setServerCertFingerprint(self: *Self, fingerprint: [32]u8) void {
        self.server_cert_fingerprint = fingerprint;
    }

    /// Start the authentication process
    /// Returns user code and verification URL for display
    pub fn startAuth(self: *Self) !struct { user_code: []const u8, verification_uri: []const u8 } {
        log.info("Starting authentication...", .{});

        self.state = .awaiting_user;

        const result = try self.oauth_client.startDeviceAuthorization();

        log.info("Please visit {s} and enter code: {s}", .{
            result.verification_uri,
            result.user_code,
        });

        self.state = .polling;

        return result;
    }

    /// Poll for authentication completion
    /// Should be called periodically until state becomes .authenticated or .failed
    pub fn poll(self: *Self) !void {
        if (self.state != .polling) {
            return;
        }

        // Check if OAuth expired
        if (!self.oauth_client.isValid()) {
            self.state = .failed;
            self.error_message = try self.allocator.dupe(u8, "Authentication timed out");
            return;
        }

        // Try to get token
        const result = self.oauth_client.pollForToken();

        if (result) |token| {
            // Got token, create session
            log.info("Token received, creating session...", .{});
            self.state = .creating_session;

            _ = try self.session_service.createSession(
                token.access_token,
                self.server_cert_fingerprint,
            );

            self.state = .authenticated;
            log.info("Authentication successful!", .{});
        } else |err| switch (err) {
            OAuthError.AuthorizationPending => {
                // Still waiting, this is expected
                log.debug("Still waiting for user authorization...", .{});
            },
            OAuthError.SlowDown => {
                // Need to slow down polling
                log.debug("Slowing down polling...", .{});
            },
            OAuthError.ExpiredToken => {
                self.state = .failed;
                self.error_message = try self.allocator.dupe(u8, "Authorization expired");
            },
            OAuthError.AccessDenied => {
                self.state = .failed;
                self.error_message = try self.allocator.dupe(u8, "Access denied by user");
            },
            else => {
                self.state = .failed;
                self.error_message = try self.allocator.dupe(u8, "Authentication error");
            },
        }
    }

    /// Check if authentication is complete
    pub fn isAuthenticated(self: *const Self) bool {
        return self.state == .authenticated;
    }

    /// Check if authentication failed
    pub fn isFailed(self: *const Self) bool {
        return self.state == .failed;
    }

    /// Get current authentication state
    pub fn getState(self: *const Self) AuthState {
        return self.state;
    }

    /// Get the current session (only valid if authenticated)
    pub fn getSession(self: *const Self) ?*const GameSession {
        if (self.state != .authenticated) {
            return null;
        }
        return self.session_service.getSession();
    }

    /// Get poll interval in seconds
    pub fn getPollInterval(self: *const Self) u32 {
        return self.oauth_client.getPollInterval();
    }

    /// Verify client authentication token
    pub fn verifyClient(self: *const Self, auth_token: []const u8) bool {
        if (self.state != .authenticated) {
            return false;
        }
        return self.session_service.verifyClientAuth(auth_token);
    }

    /// Reset authentication state
    pub fn reset(self: *Self) void {
        self.state = .idle;
        self.session_service.invalidateSession();
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }
    }

    /// Skip OAuth and create a local-only session (for testing/LAN)
    pub fn createLocalSession(self: *Self, username: []const u8) !void {
        log.info("Creating local session for: {s}", .{username});

        // Create a local token using std.Io random
        var token_buf: [32]u8 = undefined;
        const io = std.Io.Threaded.global_single_threaded.io();
        io.random(&token_buf);

        const token = try std.fmt.allocPrint(self.allocator, "local-{s}-{x}", .{
            username,
            token_buf,
        });
        defer self.allocator.free(token);

        _ = try self.session_service.createSession(token, self.server_cert_fingerprint);

        self.state = .authenticated;
    }
};

/// Convenience function to run the full authentication flow
pub fn authenticateBlocking(allocator: std.mem.Allocator, client_id: []const u8) !*const GameSession {
    var auth = AuthManager.init(allocator, client_id);
    errdefer auth.deinit();

    // Start auth
    const auth_info = try auth.startAuth();

    std.debug.print("\n", .{});
    std.debug.print("=== Hytale Server Authentication ===\n", .{});
    std.debug.print("Please visit: {s}\n", .{auth_info.verification_uri});
    std.debug.print("Enter code: {s}\n", .{auth_info.user_code});
    std.debug.print("====================================\n", .{});
    std.debug.print("\n", .{});

    // Poll until complete
    while (auth.getState() == .polling) {
        try auth.poll();

        if (auth.isFailed()) {
            return error.AuthenticationFailed;
        }

        // Wait before next poll
        std.time.sleep(auth.getPollInterval() * std.time.ns_per_s);
    }

    return auth.getSession() orelse error.NoSession;
}

// Re-exports for public API
pub const TokenResponse = @import("oauth.zig").TokenResponse;

test "auth manager init" {
    const allocator = std.testing.allocator;

    var auth = AuthManager.init(allocator, "test-client");
    defer auth.deinit();

    try std.testing.expectEqual(AuthState.idle, auth.getState());
    try std.testing.expect(!auth.isAuthenticated());
}

test "local session creation" {
    const allocator = std.testing.allocator;

    var auth = AuthManager.init(allocator, "test-client");
    defer auth.deinit();

    try auth.createLocalSession("TestPlayer");

    try std.testing.expect(auth.isAuthenticated());
    try std.testing.expect(auth.getSession() != null);
}
