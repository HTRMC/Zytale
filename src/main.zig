const std = @import("std");
const proxy = @import("proxy/proxy.zig");
const quic = @import("quic");

// Set to true to run QUIC server mode, false for proxy mode
const QUIC_SERVER_MODE = true;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (QUIC_SERVER_MODE) {
        runQuicServer(allocator);
    } else {
        runProxy(allocator);
    }
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
