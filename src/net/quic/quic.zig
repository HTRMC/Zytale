// QUIC module for Zytale
//
// This module provides QUIC support using either:
// - quiche (Cloudflare) - cross-platform, requires building from source
// - msquic (Microsoft) - Windows-native, easier to integrate
//
// For Windows development, msquic is recommended.
// Download from: https://github.com/microsoft/msquic/releases

pub const quiche = @import("quiche.zig");
pub const msquic = @import("msquic.zig");
pub const server = @import("server.zig");

pub const QuicServer = server.QuicServer;
pub const QuicConnection = server.QuicConnection;

test "quic module loads" {
    _ = quiche;
    _ = msquic;
    _ = server;
}
