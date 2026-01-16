const std = @import("std");
const proxy = @import("proxy/proxy.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Configuration (hardcoded for now, args parsing TBD for Zig 0.16)
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

    try proxy.run(allocator, listen_port, upstream_host, upstream_port, protocol);
}

test "basic test" {
    const result = std.fmt.parseInt(u16, "5520", 10);
    try std.testing.expectEqual(@as(u16, 5520), result catch unreachable);
}
