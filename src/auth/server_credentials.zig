/// Server Credentials Manager
/// Loads server authentication credentials from environment variables
const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.server_credentials);

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

    const Self = @This();

    /// Load credentials from environment variables
    /// Note: The returned credential pointers are only valid for the lifetime of the process
    pub fn fromEnvironment() Self {
        const session_token = getEnvVar("HYTALE_SERVER_SESSION_TOKEN");
        const identity_token = getEnvVar("HYTALE_SERVER_IDENTITY_TOKEN");
        const cert_fingerprint = getEnvVar("HYTALE_SERVER_CERT_FINGERPRINT");
        const audience = getEnvVar("HYTALE_SERVER_AUDIENCE") orelse "hytale-game-server";

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
        };
    }

    /// Internal thread-local buffer for environment variable conversion
    threadlocal var env_buffer: [4096]u8 = undefined;

    /// Get environment variable value (Windows-specific)
    /// Returns a slice from a thread-local buffer, valid until next call
    fn getEnvVar(name: []const u8) ?[]const u8 {
        if (builtin.os.tag == .windows) {
            // Convert name to UTF-16 for Windows API
            var name_w: [256]u16 = undefined;
            const name_w_len = std.unicode.wtf8ToWtf16Le(&name_w, name) catch return null;
            const name_w_z = name_w[0..name_w_len :0];

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

        if (self.isValid()) {
            std.debug.print("    Status: READY for authenticated clients\n", .{});
        } else {
            std.debug.print("    Status: DEVELOPMENT MODE ONLY\n", .{});
            std.debug.print("           (Set HYTALE_SERVER_SESSION_TOKEN and HYTALE_SERVER_IDENTITY_TOKEN\n", .{});
            std.debug.print("            to enable authenticated client connections)\n", .{});
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
    };

    try std.testing.expect(!creds.isValid());
    try std.testing.expect(!creds.hasCertFingerprint());
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
