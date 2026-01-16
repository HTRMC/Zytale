const std = @import("std");
const proxy = @import("proxy/proxy.zig");
const quic = @import("quic");
const auth = @import("auth");

// Set to true to run QUIC server mode, false for proxy mode
const QUIC_SERVER_MODE = true;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (QUIC_SERVER_MODE) {
        runQuicServerWithAuth(allocator);
    } else {
        runProxy(allocator);
    }
}

fn runQuicServerWithAuth(allocator: std.mem.Allocator) void {
    std.debug.print(
        \\
        \\  Zytale - Hytale Server (Zig)
        \\  ============================
        \\
    , .{});

    // Initialize auth manager
    var server_auth = auth.ServerAuth.init(allocator);
    defer server_auth.deinit();

    std.debug.print("Server Session ID: {s}\n\n", .{server_auth.server_session_id});

    // Run authentication flow
    if (!runAuthFlow(&server_auth)) {
        std.debug.print("Authentication failed or cancelled.\n", .{});
        return;
    }

    std.debug.print("\nAuthentication successful!\n", .{});

    // Now start the QUIC server
    runQuicServer(allocator);
}

fn runAuthFlow(server_auth: *auth.ServerAuth) bool {
    std.debug.print("Starting device authorization flow...\n\n", .{});

    // Start device authorization
    const device_auth = server_auth.startDeviceFlow() catch |err| {
        std.debug.print("Failed to start device flow: {}\n", .{err});
        return false;
    };

    std.debug.print(
        \\  ============================================
        \\  To authenticate, visit:
        \\  {s}
        \\
        \\  And enter code: {s}
        \\  ============================================
        \\
        \\  Waiting for authorization...
        \\
    , .{
        device_auth.verification_uri_complete orelse device_auth.verification_uri,
        device_auth.user_code,
    });

    // Poll for token
    const poll_interval_ms: u32 = device_auth.interval * 1000;
    const timeout_ms: u64 = @as(u64, device_auth.expires_in) * 1000;
    const start_time = std.time.Instant.now() catch {
        std.debug.print("Timer not supported\n", .{});
        return false;
    };

    while (true) {
        // Check if we've exceeded the timeout
        const current_time = std.time.Instant.now() catch break;
        const elapsed_ns = current_time.since(start_time);
        if (elapsed_ns / std.time.ns_per_ms >= timeout_ms) break;

        // Sleep using Windows API
        _ = std.os.windows.kernel32.SleepEx(poll_interval_ms, 0);

        const token_result = server_auth.pollDeviceToken(device_auth.device_code) catch |err| {
            std.debug.print("Poll error: {}\n", .{err});
            continue;
        };

        if (token_result) |tokens| {
            if (tokens.isSuccess()) {
                std.debug.print("Authorization received!\n", .{});

                // Store tokens
                server_auth.setOAuthTokens(tokens) catch |err| {
                    std.debug.print("Failed to store tokens: {}\n", .{err});
                    return false;
                };

                // Get profiles
                std.debug.print("Fetching game profiles...\n", .{});
                var profiles_response = server_auth.getGameProfiles() catch |err| {
                    std.debug.print("Failed to get profiles: {}\n", .{err});
                    return false;
                } orelse {
                    std.debug.print("No profiles returned\n", .{});
                    return false;
                };
                defer profiles_response.deinit();

                if (profiles_response.profiles.len == 0) {
                    std.debug.print("No game profiles found for this account.\n", .{});
                    return false;
                }

                // Display profiles
                std.debug.print("\nAvailable profiles:\n", .{});
                for (profiles_response.profiles, 0..) |profile, i| {
                    std.debug.print("  [{d}] {s} ({s})\n", .{ i + 1, profile.username, profile.uuid });
                }

                // For now, auto-select first profile
                const selected = profiles_response.profiles[0];
                std.debug.print("\nSelecting profile: {s}\n", .{selected.username});

                // Create game session
                std.debug.print("Creating game session...\n", .{});
                server_auth.createGameSession(selected.uuid) catch |err| {
                    std.debug.print("Failed to create game session: {}\n", .{err});
                    return false;
                };

                return true;
            } else if (tokens.isPending()) {
                // Still waiting
                std.debug.print(".", .{});
                continue;
            } else if (tokens.error_code) |err| {
                std.debug.print("Authorization error: {s}\n", .{err});
                return false;
            }
        }
    }

    std.debug.print("\nDevice authorization expired.\n", .{});
    return false;
}

fn runProxy(allocator: std.mem.Allocator) void {
    // Configuration (hardcoded for now)
    const listen_port: u16 = 5521; // Local proxy port
    const upstream_host: []const u8 = "127.0.0.1";
    const upstream_port: u16 = 5520; // Default Hytale server port

    // Protocol selection - use UDP for QUIC-based Hytale
    const protocol: proxy.Protocol = .udp;

    const protocol_str = if (protocol == .udp) "UDP (QUIC)" else "TCP";

    std.debug.print(
        \\
        \\  Zytale - Hytale Protocol Proxy
        \\  ==============================
        \\  Protocol: {s}
        \\  Listen:   0.0.0.0:{d}
        \\  Upstream: {s}:{d}
        \\
        \\  Point Hytale client to 127.0.0.1:{d}
        \\
    , .{ protocol_str, listen_port, upstream_host, upstream_port, listen_port });

    proxy.run(allocator, listen_port, upstream_host, upstream_port, protocol) catch |err| {
        std.debug.print("Proxy error: {}\n", .{err});
    };
}

fn runQuicServer(allocator: std.mem.Allocator) void {
    const listen_port: u16 = 5520;
    const cert_file: [:0]const u8 = "certs/server.crt";
    const key_file: [:0]const u8 = "certs/server.key";

    std.debug.print(
        \\
        \\  Zytale - QUIC Server Mode
        \\  =========================
        \\  Port: {d}
        \\  Cert: {s}
        \\  Key:  {s}
        \\
        \\  This mode terminates QUIC/TLS and logs decrypted packets.
        \\
    , .{ listen_port, cert_file, key_file });

    var server = quic.QuicServer.init(allocator);
    defer server.deinit();

    server.configure(cert_file, key_file) catch |err| {
        std.debug.print("Failed to configure QUIC server: {}\n", .{err});
        return;
    };

    server.start(listen_port) catch |err| {
        std.debug.print("Failed to start QUIC server: {}\n", .{err});
        return;
    };

    std.debug.print("QUIC server running. Press Ctrl+C to stop.\n", .{});

    // Keep running
    while (true) {
        _ = std.os.windows.kernel32.SleepEx(1000, 0); // 1 second
    }
}

test "basic test" {
    const result = std.fmt.parseInt(u16, "5520", 10);
    try std.testing.expectEqual(@as(u16, 5520), result catch unreachable);
}
