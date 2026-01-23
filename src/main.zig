const std = @import("std");
const proxy = @import("proxy/proxy.zig");
const server = @import("server/server.zig");
const auth = @import("auth/auth.zig");
const Console = @import("server/console.zig").Console;
const World = @import("world/world.zig").World;

/// Run mode
const Mode = enum {
    proxy,
    server,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Configuration (hardcoded for now)
    // Change this to .server to run as a server instead of proxy
    const mode: Mode = .server;

    switch (mode) {
        .proxy => try runProxy(allocator),
        .server => try runServer(allocator),
    }
}

fn runProxy(allocator: std.mem.Allocator) !void {
    const listen_port: u16 = 5521; // Local proxy port
    const upstream_host: []const u8 = "127.0.0.1";
    const upstream_port: u16 = 5520; // Default Hytale server port
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

    try proxy.run(allocator, listen_port, upstream_host, upstream_port, protocol);
}

fn runServer(allocator: std.mem.Allocator) !void {
    const port: u16 = 5520;

    std.debug.print(
        \\
        \\  Zytale - Hytale Server
        \\  ======================
        \\  Port: {d}
        \\
        \\  Starting server...
        \\
    , .{port});

    // Load server credentials (env vars -> disk -> none)
    var server_creds = auth.ServerCredentials.fromEnvironmentOrDisk(allocator);
    server_creds.logStatus();
    std.debug.print("\n", .{});

    // Initialize authentication
    var auth_manager = auth.AuthManager.init(allocator, auth.DEFAULT_CLIENT_ID, &server_creds);
    defer auth_manager.deinit();

    // Start console thread for commands
    var console = Console.init(allocator, &auth_manager, &server_creds);
    defer console.deinit();
    try console.start();

    // If we have valid credentials from disk, mark as authenticated
    if (server_creds.isValid()) {
        std.debug.print("  Auth: Loaded credentials for {s}\n", .{server_creds.username orelse "unknown"});
    } else if (server_creds.refresh_token != null) {
        // Try to refresh expired tokens
        std.debug.print("  Auth: Attempting to refresh expired tokens...\n", .{});
        auth_manager.refreshCredentials() catch |err| {
            std.debug.print("  Auth: Token refresh failed: {}. Use /auth login device\n", .{err});
        };
    } else {
        // No credentials, create local session for development
        std.debug.print("  Auth: No credentials found. Creating local session for development.\n", .{});
        std.debug.print("        Use /auth login device for authenticated mode.\n", .{});
        try auth_manager.createLocalSession("ServerHost");
    }

    // Initialize world
    var world = try World.init(allocator, "Flat World");
    defer world.deinit();

    const uuid_str = @import("world/world.zig").uuidToString(world.uuid);
    std.debug.print("  World: {s} (UUID: {s})\n", .{ world.name, &uuid_str });

    // Pre-generate spawn chunks
    std.debug.print("  Generating spawn chunks...\n", .{});
    const spawn = world.getSpawnPoint();
    var chunks = try world.getChunksInRadius(spawn.x, spawn.z, 6);
    defer chunks.deinit(allocator);
    std.debug.print("  Generated {d} chunks around spawn ({d}, {d})\n", .{
        chunks.items.len,
        spawn.x,
        spawn.z,
    });

    // Configure server
    const config = server.ServerConfig{
        .port = port,
        .cert_file = null, // Use test mode without cert
        .key_file = null,
        .max_connections = 100,
        .idle_timeout_ms = 30000,
        .view_radius = 6,
    };

    // Start server
    std.debug.print("\n  Starting QUIC server on port {d}...\n", .{port});
    std.debug.print("  NOTE: MsQuic DLL must be installed for server mode.\n", .{});
    std.debug.print("  Download from: https://github.com/microsoft/msquic/releases\n\n", .{});
    std.debug.print("  Type /help for available commands.\n\n", .{});

    server.runServer(allocator, config) catch |err| {
        std.debug.print("  Server error: {}\n", .{err});
        std.debug.print("\n  Server mode requires MsQuic. Falling back to proxy mode.\n\n", .{});

        // Fall back to proxy mode if server fails
        try runProxy(allocator);
    };
}

test "basic test" {
    const result = std.fmt.parseInt(u16, "5520", 10);
    try std.testing.expectEqual(@as(u16, 5520), result catch unreachable);
}
