/// Server Credentials Manager
/// Loads server authentication credentials from environment variables or disk
const std = @import("std");
const builtin = @import("builtin");

const CredentialStore = @import("credential_store.zig").CredentialStore;
const StoredCredentials = @import("credential_store.zig").StoredCredentials;

const log = std.log.scoped(.server_credentials);

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io) catch return 0;
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Source of credentials
pub const CredentialSource = enum {
    none,
    environment,
    disk,
    device_flow,
    encrypted_store,
};

/// Server credentials required for authenticated handshake with Session Service
pub const ServerCredentials = struct {
    /// Server's session token (Bearer auth for Session Service API calls)
    /// From: --session-token CLI arg or HYTALE_SERVER_SESSION_TOKEN env var
    session_token: ?[]const u8,

    /// Server's identity token (sent to clients in AuthGrant packet)
    /// From: --identity-token CLI arg or HYTALE_SERVER_IDENTITY_TOKEN env var
    identity_token: ?[]const u8,

    /// Server's X.509 certificate SHA-256 fingerprint (hex string)
    /// Used when exchanging auth grants for server access tokens
    /// From: HYTALE_SERVER_CERT_FINGERPRINT env var or computed from cert
    cert_fingerprint: ?[]const u8,

    /// Server audience string for auth grant requests
    /// Defaults to "hytale-game-server"
    audience: []const u8,

    /// Authenticated username (if available)
    username: ?[]const u8,

    /// OAuth access token (for API calls)
    access_token: ?[]const u8,

    /// OAuth refresh token (for token renewal)
    refresh_token: ?[]const u8,

    /// Token expiration timestamp
    expires_at: i64,

    /// Source of credentials
    source: CredentialSource,

    const Self = @This();

    /// Load credentials from environment variables only
    /// Note: The returned credential pointers are only valid for the lifetime of the process
    pub fn fromEnvironment() Self {
        const session_token = getEnvVar("HYTALE_SERVER_SESSION_TOKEN");
        const identity_token = getEnvVar("HYTALE_SERVER_IDENTITY_TOKEN");
        const cert_fingerprint = getEnvVar("HYTALE_SERVER_CERT_FINGERPRINT");
        const audience = getEnvVar("HYTALE_SERVER_AUDIENCE") orelse "hytale-game-server";

        const has_tokens = session_token != null and identity_token != null;

        if (session_token != null) {
            log.info("Loaded session token from environment", .{});
        }
        if (identity_token != null) {
            log.info("Loaded identity token from environment", .{});
        }
        if (cert_fingerprint != null) {
            log.info("Loaded certificate fingerprint from environment", .{});
        }

        return .{
            .session_token = session_token,
            .identity_token = identity_token,
            .cert_fingerprint = cert_fingerprint,
            .audience = audience,
            .username = null,
            .access_token = null,
            .refresh_token = null,
            .expires_at = 0,
            .source = if (has_tokens) .environment else .none,
        };
    }

    /// Load credentials from environment variables, falling back to disk
    /// Priority: Environment variables > Disk storage
    pub fn fromEnvironmentOrDisk(allocator: std.mem.Allocator) Self {
        // First try environment variables
        var creds = fromEnvironment();
        if (creds.isValid()) {
            return creds;
        }

        // Fall back to disk storage
        var store = CredentialStore.init(allocator);
        defer store.deinit();

        if (store.load()) |stored| {
            log.info("Loading credentials from disk", .{});

            // Copy stored credentials
            creds.session_token = stored.session_token;
            creds.identity_token = stored.identity_token;
            creds.access_token = stored.access_token;
            creds.refresh_token = stored.refresh_token;
            creds.expires_at = stored.expires_at;
            creds.source = .disk;

            // Username is stored separately
            if (stored.username) |name| {
                creds.username = name;
            }

            if (creds.isValid()) {
                log.info("Loaded valid credentials from disk for: {s}", .{creds.username orelse "unknown"});
            } else if (stored.canRefresh()) {
                log.info("Loaded expired credentials from disk (refresh available)", .{});
            } else {
                log.info("Loaded invalid credentials from disk", .{});
            }

            // Note: We don't free stored credentials here because creds now owns the pointers
            // The caller is responsible for managing the lifetime
            return creds;
        }

        log.info("No stored credentials found", .{});
        return creds;
    }

    /// Create empty credentials
    pub fn empty() Self {
        return .{
            .session_token = null,
            .identity_token = null,
            .cert_fingerprint = null,
            .audience = "hytale-game-server",
            .username = null,
            .access_token = null,
            .refresh_token = null,
            .expires_at = 0,
            .source = .none,
        };
    }

    /// Update credentials from device flow result
    pub fn updateFromDeviceFlow(
        self: *Self,
        allocator: std.mem.Allocator,
        session_token: []const u8,
        identity_token: []const u8,
        access_token: []const u8,
        refresh_token: ?[]const u8,
        username: []const u8,
        expires_at: i64,
    ) !void {
        // Free old values if they were allocated
        // Note: This is safe because env var pointers are static
        // and disk pointers need to be tracked separately

        self.session_token = try allocator.dupe(u8, session_token);
        self.identity_token = try allocator.dupe(u8, identity_token);
        self.access_token = try allocator.dupe(u8, access_token);
        if (refresh_token) |rt| {
            self.refresh_token = try allocator.dupe(u8, rt);
        }
        self.username = try allocator.dupe(u8, username);
        self.expires_at = expires_at;
        self.source = .device_flow;
    }

    /// Internal thread-local buffer for environment variable conversion
    threadlocal var env_buffer: [4096]u8 = undefined;

    /// Get environment variable value (Windows-specific)
    /// Returns a slice from a thread-local buffer, valid until next call
    fn getEnvVar(name: []const u8) ?[]const u8 {
        if (builtin.os.tag == .windows) {
            // Convert name to UTF-16 for Windows API with null terminator
            var name_w: [257]u16 = undefined; // Extra space for null terminator
            const name_w_len = std.unicode.wtf8ToWtf16Le(name_w[0..256], name) catch return null;
            name_w[name_w_len] = 0; // Add null terminator
            const name_w_z: [:0]const u16 = name_w[0..name_w_len :0];

            const Environ = std.process.Environ;
            if (Environ.getWindows(.{ .block = {} }, name_w_z)) |value_w| {
                // Convert UTF-16 result to UTF-8 in thread-local buffer
                const len = std.unicode.wtf16LeToWtf8(&env_buffer, value_w);
                return env_buffer[0..len];
            }
            return null;
        } else {
            // POSIX fallback (not used on Windows)
            return std.posix.getenv(name);
        }
    }

    /// Check if all required credentials for authenticated mode are present
    pub fn isValid(self: *const Self) bool {
        return self.session_token != null and self.identity_token != null;
    }

    /// Check if certificate fingerprint is available
    pub fn hasCertFingerprint(self: *const Self) bool {
        return self.cert_fingerprint != null;
    }

    /// Log credential status (without revealing actual tokens)
    pub fn logStatus(self: *const Self) void {
        std.debug.print("  Auth Credentials:\n", .{});

        const source_str = switch (self.source) {
            .none => "none",
            .environment => "environment",
            .disk => "disk",
            .device_flow => "device flow",
            .encrypted_store => "encrypted store",
        };
        std.debug.print("    Source: {s}\n", .{source_str});

        if (self.username) |name| {
            std.debug.print("    Username: {s}\n", .{name});
        }

        if (self.session_token) |token| {
            std.debug.print("    Session token: configured ({d} chars)\n", .{token.len});
        } else {
            std.debug.print("    Session token: NOT CONFIGURED\n", .{});
        }

        if (self.identity_token) |token| {
            std.debug.print("    Identity token: configured ({d} chars)\n", .{token.len});
        } else {
            std.debug.print("    Identity token: NOT CONFIGURED\n", .{});
        }

        if (self.cert_fingerprint) |fp| {
            std.debug.print("    Cert fingerprint: {s}\n", .{fp});
        } else {
            std.debug.print("    Cert fingerprint: NOT CONFIGURED\n", .{});
        }

        std.debug.print("    Audience: {s}\n", .{self.audience});

        if (self.expires_at > 0) {
            const now = getTimestamp();
            if (now < self.expires_at) {
                const remaining = self.expires_at - now;
                std.debug.print("    Expires in: {d} seconds\n", .{remaining});
            } else {
                std.debug.print("    Expires in: EXPIRED\n", .{});
            }
        }

        if (self.isValid()) {
            std.debug.print("    Status: READY for authenticated clients\n", .{});
        } else if (self.refresh_token != null) {
            std.debug.print("    Status: EXPIRED (can refresh)\n", .{});
            std.debug.print("           Use /auth refresh to renew tokens\n", .{});
        } else {
            std.debug.print("    Status: NOT AUTHENTICATED\n", .{});
            std.debug.print("           Use /auth login device to authenticate\n", .{});
        }
    }
};

/// Compute SHA-256 fingerprint of a certificate in hex format
pub fn computeCertFingerprint(allocator: std.mem.Allocator, cert_der: []const u8) ![]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cert_der, &hash, .{});

    // Convert to hex string (64 characters)
    const hex_chars = "0123456789abcdef";
    const result = try allocator.alloc(u8, 64);
    for (0..32) |i| {
        result[i * 2] = hex_chars[hash[i] >> 4];
        result[i * 2 + 1] = hex_chars[hash[i] & 0x0F];
    }
    return result;
}

test "server credentials from environment" {
    // This test just verifies the struct can be created
    // Actual environment reading can't be easily tested
    const creds = ServerCredentials{
        .session_token = "test-session",
        .identity_token = "test-identity",
        .cert_fingerprint = "abc123",
        .audience = "test-audience",
        .username = "TestUser",
        .access_token = null,
        .refresh_token = null,
        .expires_at = 0,
        .source = .environment,
    };

    try std.testing.expect(creds.isValid());
    try std.testing.expect(creds.hasCertFingerprint());
}

test "missing credentials" {
    const creds = ServerCredentials{
        .session_token = null,
        .identity_token = null,
        .cert_fingerprint = null,
        .audience = "hytale-game-server",
        .username = null,
        .access_token = null,
        .refresh_token = null,
        .expires_at = 0,
        .source = .none,
    };

    try std.testing.expect(!creds.isValid());
    try std.testing.expect(!creds.hasCertFingerprint());
}

test "empty credentials" {
    const creds = ServerCredentials.empty();

    try std.testing.expect(!creds.isValid());
    try std.testing.expect(creds.source == .none);
}

test "compute cert fingerprint" {
    const allocator = std.testing.allocator;

    // Test data (arbitrary bytes)
    const test_cert = "test certificate data";
    const fingerprint = try computeCertFingerprint(allocator, test_cert);
    defer allocator.free(fingerprint);

    // Should be 64 hex characters
    try std.testing.expectEqual(@as(usize, 64), fingerprint.len);

    // All characters should be valid hex
    for (fingerprint) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }
}
