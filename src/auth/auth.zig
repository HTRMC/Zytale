const std = @import("std");
const builtin = @import("builtin");
const OAuthClient = @import("oauth.zig").OAuthClient;
const OAuthError = @import("oauth.zig").OAuthError;
const TokenResponse = @import("oauth.zig").TokenResponse;
const SessionService = @import("session.zig").SessionService;
const GameSession = @import("session.zig").GameSession;

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io) catch return 0;
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Read a line from stdin (platform-specific)
fn readStdinLine(buf: []u8) ![]u8 {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch return error.StdinUnavailable;

        var bytes_read: u32 = 0;
        var i: usize = 0;

        while (i < buf.len - 1) {
            var char_buf: [1]u8 = undefined;
            if (windows.kernel32.ReadFile(handle, &char_buf, 1, &bytes_read, null) == windows.FALSE) {
                return error.ReadFailed;
            }
            if (bytes_read == 0) return error.EndOfStream;

            const c = char_buf[0];
            if (c == '\n') break;
            if (c == '\r') continue; // Skip CR

            buf[i] = c;
            i += 1;
        }

        return buf[0..i];
    } else {
        // POSIX - use std.posix
        const fd: std.posix.fd_t = 0; // stdin
        var i: usize = 0;

        while (i < buf.len - 1) {
            const bytes_read = std.posix.read(fd, buf[i..][0..1]) catch return error.ReadFailed;
            if (bytes_read == 0) return error.EndOfStream;

            const c = buf[i];
            if (c == '\n') break;

            i += 1;
        }

        return buf[0..i];
    }
}

// Re-export auth components
pub const SessionServiceClient = @import("session_service_client.zig").SessionServiceClient;
pub const SessionServiceError = @import("session_service_client.zig").SessionServiceError;
pub const GameProfile = @import("session_service_client.zig").GameProfile;
pub const GameSessionResponse = @import("session_service_client.zig").GameSessionResponse;
pub const ServerCredentials = @import("server_credentials.zig").ServerCredentials;
pub const CredentialSource = @import("server_credentials.zig").CredentialSource;
pub const computeCertFingerprint = @import("server_credentials.zig").computeCertFingerprint;
pub const CredentialStore = @import("credential_store.zig").CredentialStore;
pub const StoredCredentials = @import("credential_store.zig").StoredCredentials;
pub const DEFAULT_CLIENT_ID = @import("oauth.zig").DEFAULT_CLIENT_ID;

const log = std.log.scoped(.auth);

/// Authentication state machine
pub const AuthState = enum {
    /// Not authenticated, waiting to start
    idle,
    /// Device authorization started, waiting for user
    awaiting_user,
    /// Polling for token
    polling,
    /// Token received, fetching profiles
    fetching_profiles,
    /// Waiting for profile selection
    awaiting_profile_selection,
    /// Creating session
    creating_session,
    /// Fully authenticated
    authenticated,
    /// Authentication failed
    failed,
};

/// Device flow result for profile selection
pub const DeviceFlowProfiles = struct {
    profiles: []GameProfile,
    access_token: []const u8,
    refresh_token: ?[]const u8,
    id_token: ?[]const u8,
};

/// Server authentication manager
/// Orchestrates OAuth device flow and session creation
pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    oauth_client: OAuthClient,
    session_service: SessionService,
    session_service_client: SessionServiceClient,
    credential_store: CredentialStore,
    state: AuthState,

    /// Current server credentials
    credentials: *ServerCredentials,

    /// Pending profiles from device flow (before selection)
    pending_profiles: ?[]GameProfile,

    /// Pending tokens from device flow (before session creation)
    pending_access_token: ?[]const u8,
    pending_refresh_token: ?[]const u8,
    pending_id_token: ?[]const u8,

    /// Server certificate fingerprint for session binding
    server_cert_fingerprint: [32]u8,

    /// Error message if authentication failed
    error_message: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, credentials: *ServerCredentials) Self {
        return .{
            .allocator = allocator,
            .oauth_client = OAuthClient.init(allocator, client_id, null),
            .session_service = SessionService.init(allocator),
            .session_service_client = SessionServiceClient.init(allocator),
            .credential_store = CredentialStore.init(allocator),
            .state = .idle,
            .credentials = credentials,
            .pending_profiles = null,
            .pending_access_token = null,
            .pending_refresh_token = null,
            .pending_id_token = null,
            .server_cert_fingerprint = [_]u8{0} ** 32,
            .error_message = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.oauth_client.deinit();
        self.session_service.deinit();
        self.session_service_client.deinit();
        self.credential_store.deinit();
        self.freePendingData();
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    fn freePendingData(self: *Self) void {
        if (self.pending_profiles) |profiles| {
            self.session_service_client.freeProfiles(profiles);
            self.pending_profiles = null;
        }
        if (self.pending_access_token) |token| {
            self.allocator.free(token);
            self.pending_access_token = null;
        }
        if (self.pending_refresh_token) |token| {
            self.allocator.free(token);
            self.pending_refresh_token = null;
        }
        if (self.pending_id_token) |token| {
            self.allocator.free(token);
            self.pending_id_token = null;
        }
    }

    /// Set server certificate fingerprint for session binding
    pub fn setServerCertFingerprint(self: *Self, fingerprint: [32]u8) void {
        self.server_cert_fingerprint = fingerprint;
    }

    /// Start the device authorization flow
    /// Returns user code and verification URL for display
    pub fn startDeviceFlow(self: *Self) !struct { user_code: []const u8, verification_uri: []const u8 } {
        log.info("Starting device authorization flow...", .{});

        self.freePendingData();
        self.state = .awaiting_user;

        const result = self.oauth_client.startDeviceAuthorization() catch |err| {
            self.state = .failed;
            self.error_message = try self.allocator.dupe(u8, switch (err) {
                OAuthError.NetworkError => "Failed to connect to authentication server",
                OAuthError.ParseError => "Invalid response from authentication server",
                else => "Device authorization failed",
            });
            return err;
        };

        self.state = .polling;

        log.info("Device authorization started", .{});
        log.info("  User code: {s}", .{result.user_code});
        log.info("  Visit: {s}", .{result.verification_uri});

        return .{
            .user_code = result.user_code,
            .verification_uri = result.verification_uri,
        };
    }

    /// Poll for token during device flow
    /// Returns true when token is received, false when still waiting
    pub fn pollDeviceFlow(self: *Self) !bool {
        if (self.state != .polling) {
            return false;
        }

        // Check if OAuth expired
        if (!self.oauth_client.isValid()) {
            self.state = .failed;
            self.error_message = try self.allocator.dupe(u8, "Authentication timed out");
            return error.Timeout;
        }

        // Try to get token
        const result = self.oauth_client.pollForToken();

        if (result) |token| {
            log.info("Token received, fetching profiles...", .{});
            self.state = .fetching_profiles;

            // Store tokens
            self.pending_access_token = try self.allocator.dupe(u8, token.access_token);
            if (token.refresh_token) |rt| {
                self.pending_refresh_token = try self.allocator.dupe(u8, rt);
            }
            if (token.id_token) |it| {
                self.pending_id_token = try self.allocator.dupe(u8, it);
            }

            // Fetch profiles
            try self.fetchProfiles();
            return true;
        } else |err| switch (err) {
            OAuthError.AuthorizationPending => {
                // Still waiting, this is expected
                return false;
            },
            OAuthError.SlowDown => {
                // Need to slow down polling
                log.debug("Slowing down polling...", .{});
                return false;
            },
            OAuthError.ExpiredToken => {
                self.state = .failed;
                self.error_message = try self.allocator.dupe(u8, "Authorization expired");
                return error.Expired;
            },
            OAuthError.AccessDenied => {
                self.state = .failed;
                self.error_message = try self.allocator.dupe(u8, "Access denied by user");
                return error.AccessDenied;
            },
            else => {
                self.state = .failed;
                self.error_message = try self.allocator.dupe(u8, "Authentication error");
                return error.AuthError;
            },
        }
    }

    /// Fetch game profiles after token is received
    fn fetchProfiles(self: *Self) !void {
        const access_token = self.pending_access_token orelse return error.NoToken;

        const profiles = self.session_service_client.getGameProfiles(access_token) catch |err| {
            self.state = .failed;
            self.error_message = try self.allocator.dupe(u8, switch (err) {
                SessionServiceError.AuthenticationFailed => "Access token rejected",
                SessionServiceError.NoProfiles => "No game profiles found",
                else => "Failed to fetch profiles",
            });
            return error.ProfileFetchFailed;
        };

        self.pending_profiles = profiles;

        if (profiles.len == 1) {
            // Single profile, auto-select it
            log.info("Found single profile: {s}", .{profiles[0].username});
            try self.selectProfile(0);
        } else {
            // Multiple profiles, wait for selection
            self.state = .awaiting_profile_selection;
            log.info("Found {d} profiles, awaiting selection", .{profiles.len});
            for (profiles, 0..) |profile, i| {
                log.info("  [{d}] {s}", .{ i, profile.username });
            }
        }
    }

    /// Get pending profiles for selection (only valid in awaiting_profile_selection state)
    pub fn getPendingProfiles(self: *const Self) ?[]const GameProfile {
        if (self.state != .awaiting_profile_selection) {
            return null;
        }
        return self.pending_profiles;
    }

    /// Select a profile by index
    pub fn selectProfile(self: *Self, index: usize) !void {
        const profiles = self.pending_profiles orelse return error.NoProfiles;
        if (index >= profiles.len) return error.InvalidIndex;

        const profile = profiles[index];
        const access_token = self.pending_access_token orelse return error.NoToken;

        log.info("Selected profile: {s}", .{profile.username});
        self.state = .creating_session;

        // Create game session
        var game_session = self.session_service_client.createGameSession(
            access_token,
            profile.uuid,
        ) catch |err| {
            self.state = .failed;
            self.error_message = try self.allocator.dupe(u8, switch (err) {
                SessionServiceError.AuthenticationFailed => "Failed to create session: access denied",
                else => "Failed to create game session",
            });
            return error.SessionCreationFailed;
        };
        defer self.session_service_client.freeGameSession(&game_session);

        // Update credentials
        try self.credentials.updateFromDeviceFlow(
            self.allocator,
            game_session.session_token,
            game_session.identity_token,
            access_token,
            self.pending_refresh_token,
            profile.username,
            game_session.expires_at,
        );

        // Save to disk
        try self.saveCredentials();

        self.state = .authenticated;
        log.info("Authentication successful! Logged in as: {s}", .{profile.username});
    }

    /// Save current credentials to disk
    pub fn saveCredentials(self: *Self) !void {
        const creds = self.credentials;

        const stored = StoredCredentials{
            .session_token = creds.session_token,
            .identity_token = creds.identity_token,
            .access_token = creds.access_token,
            .refresh_token = creds.refresh_token,
            .username = creds.username,
            .expires_at = creds.expires_at,
        };

        try self.credential_store.save(&stored);
    }

    /// Refresh expired tokens using refresh token
    pub fn refreshCredentials(self: *Self) !void {
        const refresh_token = self.credentials.refresh_token orelse {
            log.warn("No refresh token available", .{});
            return error.NoRefreshToken;
        };

        log.info("Refreshing access token...", .{});

        const token = self.oauth_client.refreshToken(refresh_token) catch |err| {
            log.err("Token refresh failed: {}", .{err});
            return error.RefreshFailed;
        };

        // Update credentials with new access token
        if (self.credentials.access_token) |old| {
            self.allocator.free(old);
        }
        self.credentials.access_token = try self.allocator.dupe(u8, token.access_token);

        if (token.refresh_token) |new_rt| {
            if (self.credentials.refresh_token) |old| {
                self.allocator.free(old);
            }
            self.credentials.refresh_token = try self.allocator.dupe(u8, new_rt);
        }

        // Update expiration
        self.credentials.expires_at = getTimestamp() + @as(i64, token.expires_in);

        // Re-create game session with new access token
        // This is needed because the session token may have expired too
        // For now, we'll just save the updated credentials

        try self.saveCredentials();
        log.info("Token refreshed successfully", .{});
    }

    /// Clear stored credentials (logout)
    pub fn logout(self: *Self) void {
        log.info("Logging out...", .{});

        // Clear disk storage
        self.credential_store.clear();

        // Reset state
        self.state = .idle;
        self.freePendingData();

        log.info("Logged out successfully", .{});
    }

    /// Check if authentication is complete
    pub fn isAuthenticated(self: *const Self) bool {
        return self.state == .authenticated or self.credentials.isValid();
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
        if (!self.isAuthenticated()) {
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
        if (!self.isAuthenticated()) {
            return false;
        }
        return self.session_service.verifyClientAuth(auth_token);
    }

    /// Reset authentication state
    pub fn reset(self: *Self) void {
        self.state = .idle;
        self.session_service.invalidateSession();
        self.freePendingData();
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

    /// Get error message (if in failed state)
    pub fn getErrorMessage(self: *const Self) ?[]const u8 {
        return self.error_message;
    }
};

/// Run the complete device flow blocking
/// This is a convenience function for simple use cases
pub fn runDeviceFlowBlocking(allocator: std.mem.Allocator, credentials: *ServerCredentials) !void {
    var auth = AuthManager.init(allocator, DEFAULT_CLIENT_ID, credentials);
    defer auth.deinit();

    // Start auth
    const auth_info = try auth.startDeviceFlow();

    std.debug.print("\n", .{});
    std.debug.print("=== Hytale Server Authentication ===\n", .{});
    std.debug.print("Please visit: {s}\n", .{auth_info.verification_uri});
    std.debug.print("Enter code: {s}\n", .{auth_info.user_code});
    std.debug.print("====================================\n", .{});
    std.debug.print("\n", .{});

    // Poll until token received
    while (auth.getState() == .polling) {
        if (auth.pollDeviceFlow()) |got_token| {
            if (got_token) break;
        } else |err| {
            std.debug.print("Authentication failed: {}\n", .{err});
            if (auth.getErrorMessage()) |msg| {
                std.debug.print("  {s}\n", .{msg});
            }
            return error.AuthenticationFailed;
        }

        // Wait before next poll
        const sleep_io = std.Io.Threaded.global_single_threaded.io();
        std.Io.sleep(sleep_io, std.Io.Duration.fromSeconds(auth.getPollInterval()), .awake) catch {};
    }

    // Handle profile selection if needed
    if (auth.getState() == .awaiting_profile_selection) {
        if (auth.getPendingProfiles()) |profiles| {
            std.debug.print("\nSelect a profile:\n", .{});
            for (profiles, 0..) |profile, i| {
                std.debug.print("  [{d}] {s}\n", .{ i, profile.username });
            }
            std.debug.print("\nEnter number (0-{d}): ", .{profiles.len - 1});

            // Read selection from stdin
            var buf: [16]u8 = undefined;
            if (readStdinLine(&buf)) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (std.fmt.parseInt(usize, trimmed, 10)) |index| {
                    try auth.selectProfile(index);
                } else |_| {
                    std.debug.print("Invalid selection\n", .{});
                    return error.InvalidSelection;
                }
            } else |_| {
                return error.InputError;
            }
        }
    }

    if (auth.isAuthenticated()) {
        std.debug.print("\nAuthentication successful!\n", .{});
        std.debug.print("Logged in as: {s}\n", .{credentials.username orelse "unknown"});
    } else {
        return error.AuthenticationFailed;
    }
}

// Re-exports for public API
pub const OAuthClient_TokenResponse = TokenResponse;

test "auth manager init" {
    const allocator = std.testing.allocator;

    var creds = ServerCredentials.empty();
    var auth = AuthManager.init(allocator, "test-client", &creds);
    defer auth.deinit();

    try std.testing.expectEqual(AuthState.idle, auth.getState());
    try std.testing.expect(!auth.isAuthenticated());
}

test "local session creation" {
    const allocator = std.testing.allocator;

    var creds = ServerCredentials.empty();
    var auth = AuthManager.init(allocator, "test-client", &creds);
    defer auth.deinit();

    try auth.createLocalSession("TestPlayer");

    try std.testing.expect(auth.isAuthenticated());
    try std.testing.expect(auth.getSession() != null);
}
