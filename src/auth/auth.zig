const std = @import("std");
const builtin = @import("builtin");
const OAuthClient = @import("oauth.zig").OAuthClient;
const OAuthError = @import("oauth.zig").OAuthError;
const TokenResponse = @import("oauth.zig").TokenResponse;
const SessionService = @import("session.zig").SessionService;
const GameSession = @import("session.zig").GameSession;
const EncryptedCredentialStore = @import("encrypted_credential_store.zig").EncryptedCredentialStore;
const EncryptedStoredCredentials = @import("encrypted_credential_store.zig").StoredCredentials;
const MemoryCredentialStore = @import("memory_credential_store.zig").MemoryCredentialStore;

/// Token refresh buffer in seconds (refresh 300 seconds before expiry, matching Java)
const REFRESH_BUFFER_SECONDS: i64 = 300;

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io);
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Read a line from stdin (platform-specific)
fn readStdinLine(buf: []u8) ![]u8 {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const handle = windows.peb().ProcessParameters.hStdInput;

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
pub const DEFAULT_CLIENT_ID = @import("oauth.zig").DEFAULT_CLIENT_ID;

// Re-export credential stores
pub const encrypted_credential_store = @import("encrypted_credential_store.zig");
pub const memory_credential_store = @import("memory_credential_store.zig");
pub const machine_id = @import("machine_id.zig");

const log = std.log.scoped(.auth);

/// Authentication mode (matching Java ServerAuthManager.AuthMode)
pub const AuthMode = enum {
    /// Not authenticated
    none,
    /// Singleplayer mode with owner-provided tokens
    singleplayer,
    /// External session tokens (CLI/env vars)
    external_session,
    /// OAuth browser flow (not implemented in Zig)
    oauth_browser,
    /// OAuth device flow
    oauth_device,
    /// Restored from encrypted storage
    oauth_store,

    pub fn toString(self: AuthMode) []const u8 {
        return switch (self) {
            .none => "NONE",
            .singleplayer => "SINGLEPLAYER",
            .external_session => "EXTERNAL_SESSION",
            .oauth_browser => "OAUTH_BROWSER",
            .oauth_device => "OAUTH_DEVICE",
            .oauth_store => "OAUTH_STORE",
        };
    }
};

/// Credential storage type (matching Java persistence options)
pub const AuthCredentialStoreType = enum {
    /// Memory-only storage (credentials lost on restart)
    memory,
    /// Encrypted file storage (persists across restarts)
    encrypted,

    pub fn toString(self: AuthCredentialStoreType) []const u8 {
        return switch (self) {
            .memory => "Memory",
            .encrypted => "Encrypted",
        };
    }
};

/// Result of authentication attempt
pub const AuthResult = enum {
    /// Authentication successful
    success,
    /// Waiting for profile selection
    pending_profile_selection,
    /// Authentication failed
    failed,
};

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
    encrypted_store: EncryptedCredentialStore,
    memory_store: ?MemoryCredentialStore,
    store_type: AuthCredentialStoreType,
    state: AuthState,

    /// Current authentication mode
    auth_mode: AuthMode,

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

    /// Token expiration timestamp for refresh scheduling
    token_expiry: i64,

    /// Selected profile UUID (stored for session recreation)
    selected_profile_uuid: ?[16]u8,

    /// Available profiles (cached after fetch)
    available_profiles: ?[]GameProfile,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, credentials: *ServerCredentials) Self {
        return .{
            .allocator = allocator,
            .oauth_client = OAuthClient.init(allocator, client_id, null),
            .session_service = SessionService.init(allocator),
            .session_service_client = SessionServiceClient.init(allocator),
            .encrypted_store = EncryptedCredentialStore.init(allocator),
            .memory_store = null,
            .store_type = .encrypted,
            .state = .idle,
            .auth_mode = .none,
            .credentials = credentials,
            .pending_profiles = null,
            .pending_access_token = null,
            .pending_refresh_token = null,
            .pending_id_token = null,
            .server_cert_fingerprint = [_]u8{0} ** 32,
            .error_message = null,
            .token_expiry = 0,
            .selected_profile_uuid = null,
            .available_profiles = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.oauth_client.deinit();
        self.session_service.deinit();
        self.session_service_client.deinit();
        self.encrypted_store.deinit();
        if (self.memory_store) |*store| {
            store.deinit();
        }
        self.freePendingData();
        if (self.available_profiles) |profiles| {
            self.session_service_client.freeProfiles(profiles);
        }
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

        // Store profile UUID and expiry
        self.selected_profile_uuid = profile.uuid;
        self.token_expiry = game_session.expires_at;
        self.auth_mode = .oauth_device;

        // Save to encrypted storage
        self.saveToEncryptedStore() catch |err| {
            log.warn("Failed to save to encrypted store: {}", .{err});
        };

        self.state = .authenticated;
        log.info("Authentication successful! Logged in as: {s}", .{profile.username});
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

        try self.saveToEncryptedStore();
        log.info("Token refreshed successfully", .{});
    }

    /// Clear stored credentials (logout)
    pub fn logout(self: *Self) void {
        log.info("Logging out...", .{});

        // Clear both stores
        self.encrypted_store.clear();
        if (self.memory_store) |*store| {
            store.clear();
        }

        // Reset state
        self.state = .idle;
        self.auth_mode = .none;
        self.token_expiry = 0;
        self.selected_profile_uuid = null;
        self.freePendingData();

        if (self.available_profiles) |profiles| {
            self.session_service_client.freeProfiles(profiles);
            self.available_profiles = null;
        }

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

    /// Get current authentication mode
    pub fn getAuthMode(self: *const Self) AuthMode {
        return self.auth_mode;
    }

    /// Get current credential store type
    pub fn getStoreType(self: *const Self) AuthCredentialStoreType {
        return self.store_type;
    }

    /// Set credential store type
    /// Migrates existing credentials to the new store
    pub fn setStoreType(self: *Self, store_type: AuthCredentialStoreType) !void {
        if (self.store_type == store_type) {
            log.info("Already using {s} storage", .{store_type.toString()});
            return;
        }

        log.info("Switching credential storage from {s} to {s}", .{
            self.store_type.toString(),
            store_type.toString(),
        });

        // Build current credentials for migration
        const current_creds = EncryptedStoredCredentials{
            .access_token = self.credentials.access_token,
            .refresh_token = self.credentials.refresh_token,
            .expires_at = self.credentials.expires_at,
            .profile_uuid = self.selected_profile_uuid,
            .username = self.credentials.username,
        };

        const has_credentials = current_creds.canRefresh() or current_creds.access_token != null;

        switch (store_type) {
            .memory => {
                // Switching to memory-only storage
                // Initialize memory store if needed
                if (self.memory_store == null) {
                    self.memory_store = MemoryCredentialStore.init(self.allocator);
                }

                // Copy current credentials to memory
                if (has_credentials) {
                    try self.memory_store.?.save(&current_creds);
                }

                // Clear encrypted store (credentials no longer persisted)
                self.encrypted_store.clear();

                log.warn("Credentials will NOT be persisted. They will be lost on restart.", .{});
            },
            .encrypted => {
                // Switching to encrypted storage
                if (!self.encrypted_store.isEncryptionAvailable()) {
                    log.err("Encrypted storage not available (no machine ID)", .{});
                    return error.EncryptionUnavailable;
                }

                // Save current credentials to encrypted store
                if (has_credentials) {
                    try self.encrypted_store.save(&current_creds);
                }

                // Clear memory store
                if (self.memory_store) |*store| {
                    store.clear();
                }

                log.info("Credentials will be persisted to encrypted storage", .{});
            },
        }

        self.store_type = store_type;
        log.info("Now using {s} storage", .{store_type.toString()});
    }

    /// Initialize from encrypted credential store on startup
    /// Attempts to restore session from stored credentials
    /// Returns the result of the restoration attempt
    pub fn initializeFromStore(self: *Self) AuthResult {
        if (!self.encrypted_store.isEncryptionAvailable()) {
            log.warn("Encryption not available, cannot restore from store", .{});
            return .failed;
        }

        // Load stored credentials
        var stored = self.encrypted_store.load() orelse {
            log.debug("No stored credentials found", .{});
            return .failed;
        };
        defer self.encrypted_store.freeCredentials(&stored);

        // Check if we have a refresh token
        if (!stored.canRefresh()) {
            log.info("Stored credentials have no refresh token", .{});
            return .failed;
        }

        log.info("Found stored credentials, attempting to restore session...", .{});

        // Store the refresh token for use
        self.pending_refresh_token = self.allocator.dupe(u8, stored.refresh_token.?) catch {
            log.err("Failed to allocate refresh token", .{});
            return .failed;
        };

        // Store the access token if still valid
        if (stored.isAccessTokenValid()) {
            if (stored.access_token) |token| {
                self.pending_access_token = self.allocator.dupe(u8, token) catch null;
            }
        }

        // Store profile UUID if we had one selected
        self.selected_profile_uuid = stored.profile_uuid;

        // Try to refresh tokens first
        if (!stored.isAccessTokenValid()) {
            log.info("Access token expired, refreshing...", .{});
            self.refreshCredentials() catch |err| {
                log.warn("Failed to refresh tokens: {}", .{err});
                self.freePendingData();
                return .failed;
            };
        } else {
            // Update credentials with stored access token
            if (stored.access_token) |token| {
                self.credentials.access_token = self.allocator.dupe(u8, token) catch null;
            }
            self.credentials.expires_at = stored.expires_at;
        }

        // Fetch profiles and try to restore session
        return self.createGameSessionFromOAuth(.oauth_store);
    }

    /// Create game session from OAuth tokens (internal)
    fn createGameSessionFromOAuth(self: *Self, mode: AuthMode) AuthResult {
        const access_token = self.pending_access_token orelse self.credentials.access_token orelse {
            log.warn("No access token available for session creation", .{});
            return .failed;
        };

        // Fetch game profiles
        const profiles = self.session_service_client.getGameProfiles(access_token) catch |err| {
            log.warn("Failed to fetch game profiles: {}", .{err});
            return .failed;
        };

        // Store profiles
        if (self.available_profiles) |old| {
            self.session_service_client.freeProfiles(old);
        }
        self.available_profiles = profiles;

        if (profiles.len == 0) {
            log.warn("No game profiles found for this account", .{});
            return .failed;
        }

        // Try auto-select profile
        if (self.tryAutoSelectProfile(profiles)) |profile| {
            if (self.completeAuthWithProfile(profile, mode)) {
                return .success;
            }
            return .failed;
        }

        // Multiple profiles, need selection
        self.pending_profiles = profiles;
        self.state = .awaiting_profile_selection;

        log.info("Multiple profiles available. Use '/auth select <username>' to choose:", .{});
        for (profiles, 0..) |profile, i| {
            log.info("  [{d}] {s}", .{ i + 1, profile.username });
        }

        return .pending_profile_selection;
    }

    /// Try to auto-select a profile based on stored UUID or single profile
    fn tryAutoSelectProfile(self: *Self, profiles: []const GameProfile) ?GameProfile {
        // Single profile - auto select
        if (profiles.len == 1) {
            log.info("Auto-selected profile: {s}", .{profiles[0].username});
            return profiles[0];
        }

        // Check if we have a stored profile UUID
        if (self.selected_profile_uuid) |stored_uuid| {
            for (profiles) |profile| {
                if (std.mem.eql(u8, &profile.uuid, &stored_uuid)) {
                    log.info("Auto-selected profile from storage: {s}", .{profile.username});
                    return profile;
                }
            }
        }

        return null;
    }

    /// Complete authentication with a selected profile
    fn completeAuthWithProfile(self: *Self, profile: GameProfile, mode: AuthMode) bool {
        const access_token = self.pending_access_token orelse self.credentials.access_token orelse {
            log.warn("No access token for profile authentication", .{});
            return false;
        };

        // Create game session
        var game_session = self.session_service_client.createGameSession(
            access_token,
            profile.uuid,
        ) catch |err| {
            log.warn("Failed to create game session: {}", .{err});
            return false;
        };
        defer self.session_service_client.freeGameSession(&game_session);

        // Update credentials
        self.credentials.updateFromDeviceFlow(
            self.allocator,
            game_session.session_token,
            game_session.identity_token,
            access_token,
            self.pending_refresh_token,
            profile.username,
            game_session.expires_at,
        ) catch |err| {
            log.err("Failed to update credentials: {}", .{err});
            return false;
        };

        // Store profile UUID
        self.selected_profile_uuid = profile.uuid;
        self.token_expiry = game_session.expires_at;
        self.auth_mode = mode;
        self.state = .authenticated;

        // Save to encrypted storage
        self.saveToEncryptedStore() catch |err| {
            log.warn("Failed to save to encrypted store: {}", .{err});
        };

        log.info("Authentication successful! Mode: {s}", .{mode.toString()});
        return true;
    }

    /// Save current credentials to the active store
    pub fn saveToEncryptedStore(self: *Self) !void {
        const stored = EncryptedStoredCredentials{
            .access_token = self.credentials.access_token,
            .refresh_token = self.credentials.refresh_token,
            .expires_at = self.credentials.expires_at,
            .profile_uuid = self.selected_profile_uuid,
            .username = self.credentials.username,
        };

        switch (self.store_type) {
            .encrypted => try self.encrypted_store.save(&stored),
            .memory => {
                if (self.memory_store == null) {
                    self.memory_store = MemoryCredentialStore.init(self.allocator);
                }
                try self.memory_store.?.save(&stored);
            },
        }
    }

    /// Check if tokens need refresh and refresh if needed
    /// Call this periodically (e.g., every minute) to keep session alive
    pub fn checkAndRefresh(self: *Self) !void {
        if (self.auth_mode == .none or self.auth_mode == .singleplayer) {
            return;
        }

        const now = getTimestamp();
        const time_until_expiry = self.token_expiry - now;

        // Refresh 300 seconds before expiry (matching Java)
        if (time_until_expiry <= REFRESH_BUFFER_SECONDS and time_until_expiry > 0) {
            log.info("Token expiring soon, refreshing...", .{});
            try self.doRefresh();
        } else if (time_until_expiry <= 0) {
            log.warn("Token expired, attempting refresh...", .{});
            try self.doRefresh();
        }
    }

    /// Perform token refresh
    fn doRefresh(self: *Self) !void {
        // First try to refresh the game session
        if (self.credentials.session_token) |session_token| {
            _ = session_token;
            // Note: Session refresh API would go here if available
        }

        // Refresh via OAuth
        try self.refreshGameSessionViaOAuth();
    }

    /// Refresh game session using OAuth tokens
    fn refreshGameSessionViaOAuth(self: *Self) !void {
        // Only supported for OAuth modes
        switch (self.auth_mode) {
            .oauth_browser, .oauth_device, .oauth_store => {},
            else => {
                log.warn("Refresh via OAuth not supported for current auth mode", .{});
                return error.UnsupportedAuthMode;
            },
        }

        const profile_uuid = self.selected_profile_uuid orelse {
            log.warn("No profile selected, cannot refresh game session", .{});
            return error.NoProfile;
        };

        // Refresh OAuth tokens first
        try self.refreshCredentials();

        // Create new game session
        const access_token = self.credentials.access_token orelse return error.NoAccessToken;

        var game_session = self.session_service_client.createGameSession(
            access_token,
            profile_uuid,
        ) catch |err| {
            log.err("Failed to create new game session: {}", .{err});
            return error.SessionCreationFailed;
        };
        defer self.session_service_client.freeGameSession(&game_session);

        // Update credentials
        if (self.credentials.session_token) |old| {
            self.allocator.free(old);
        }
        self.credentials.session_token = try self.allocator.dupe(u8, game_session.session_token);

        if (self.credentials.identity_token) |old| {
            self.allocator.free(old);
        }
        self.credentials.identity_token = try self.allocator.dupe(u8, game_session.identity_token);

        self.credentials.expires_at = game_session.expires_at;
        self.token_expiry = game_session.expires_at;

        // Save to encrypted storage
        try self.saveToEncryptedStore();

        log.info("Game session refreshed via OAuth", .{});
    }

    /// List available profiles (requires valid access token)
    pub fn listProfiles(self: *Self) ![]const GameProfile {
        const access_token = self.credentials.access_token orelse {
            return error.NoAccessToken;
        };

        const profiles = try self.session_service_client.getGameProfiles(access_token);

        // Update cached profiles
        if (self.available_profiles) |old| {
            self.session_service_client.freeProfiles(old);
        }
        self.available_profiles = profiles;

        return profiles;
    }

    /// Select a profile by username
    pub fn selectProfileByUsername(self: *Self, username: []const u8) !void {
        const profiles = self.pending_profiles orelse self.available_profiles orelse {
            return error.NoProfiles;
        };

        for (profiles) |profile| {
            if (std.ascii.eqlIgnoreCase(profile.username, username)) {
                log.info("Selected profile: {s}", .{profile.username});

                if (self.completeAuthWithProfile(profile, self.auth_mode)) {
                    self.pending_profiles = null;
                    return;
                }
                return error.SessionCreationFailed;
            }
        }

        log.warn("No profile found with username: {s}", .{username});
        return error.ProfileNotFound;
    }

    /// Get seconds until token expiry
    pub fn getSecondsUntilExpiry(self: *const Self) i64 {
        if (self.token_expiry == 0) return 0;
        const now = getTimestamp();
        return @max(0, self.token_expiry - now);
    }

    /// Get authentication status string
    pub fn getAuthStatus(self: *const Self) []const u8 {
        if (self.state == .authenticated) {
            return "authenticated";
        } else if (self.state == .awaiting_profile_selection) {
            return "awaiting profile selection";
        } else if (self.state == .failed) {
            return "failed";
        } else if (self.auth_mode == .none) {
            return "not authenticated";
        } else {
            return "partial";
        }
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
