const std = @import("std");
const builtin = @import("builtin");
const frame = @import("../net/packet/frame.zig");

const log = std.log.scoped(.proxy);

pub const Protocol = enum { tcp, udp };

// Windows socket types
const ws2 = std.os.windows.ws2_32;
const SOCKET = ws2.SOCKET;
const INVALID_SOCKET = ws2.INVALID_SOCKET;
const SOCKET_ERROR: i32 = -1;
const AF = ws2.AF;
const SOCK = ws2.SOCK;
const IPPROTO = ws2.IPPROTO;
const SOL_SOCKET: i32 = 0xFFFF;
const SO_REUSEADDR: i32 = 4;

pub fn run(allocator: std.mem.Allocator, listen_port: u16, upstream_host: []const u8, upstream_port: u16, protocol: Protocol) !void {
    switch (protocol) {
        .tcp => try runTcpWindows(allocator, listen_port, upstream_host, upstream_port),
        .udp => try runUdpWindows(allocator, listen_port, upstream_host, upstream_port),
    }
}

fn runUdpWindows(allocator: std.mem.Allocator, listen_port: u16, upstream_host: []const u8, upstream_port: u16) !void {
    _ = allocator;

    // Initialize Winsock
    var wsa_data: ws2.WSADATA = undefined;
    const wsa_result = ws2.WSAStartup(0x0202, &wsa_data);
    if (wsa_result != 0) {
        log.err("WSAStartup failed: {}", .{wsa_result});
        return error.WinsockInitFailed;
    }
    defer _ = ws2.WSACleanup();

    log.info("Winsock initialized", .{});

    // Create UDP socket for listening
    const listen_sock = ws2.socket(AF.INET, SOCK.DGRAM, IPPROTO.UDP);
    if (listen_sock == INVALID_SOCKET) {
        const err = ws2.WSAGetLastError();
        log.err("Failed to create socket: {}", .{err});
        return error.SocketCreationFailed;
    }
    defer _ = ws2.closesocket(listen_sock);

    // Enable address reuse
    var reuse: i32 = 1;
    _ = ws2.setsockopt(listen_sock, SOL_SOCKET, SO_REUSEADDR, @ptrCast(&reuse), @sizeOf(i32));

    // Bind to listen port
    var listen_addr: ws2.sockaddr.in = .{
        .port = ws2.htons(listen_port),
        .addr = 0, // INADDR_ANY
    };

    if (ws2.bind(listen_sock, @ptrCast(&listen_addr), @sizeOf(ws2.sockaddr.in)) == SOCKET_ERROR) {
        const err = ws2.WSAGetLastError();
        log.err("Failed to bind: {}", .{err});
        return error.BindFailed;
    }

    // Parse upstream address
    var upstream_addr: ws2.sockaddr.in = .{
        .port = ws2.htons(upstream_port),
        .addr = parseIpv4(upstream_host) catch |err| {
            log.err("Failed to parse upstream host: {}", .{err});
            return err;
        },
    };

    // Create socket for upstream communication
    const upstream_sock = ws2.socket(AF.INET, SOCK.DGRAM, IPPROTO.UDP);
    if (upstream_sock == INVALID_SOCKET) {
        const err = ws2.WSAGetLastError();
        log.err("Failed to create upstream socket: {}", .{err});
        return error.SocketCreationFailed;
    }
    defer _ = ws2.closesocket(upstream_sock);

    log.info("UDP: Listening on port {d}, forwarding to {s}:{d}...", .{ listen_port, upstream_host, upstream_port });

    // Use select() for non-blocking I/O on both sockets
    var recv_buf: [65536]u8 = undefined;
    var packet_count: u64 = 0;
    var last_client_addr: ws2.sockaddr.in = undefined;
    var have_client: bool = false;

    while (true) {
        // Set up fd_set for select
        var read_fds: ws2.fd_set = .{ .fd_count = 2, .fd_array = undefined };
        read_fds.fd_array[0] = listen_sock;
        read_fds.fd_array[1] = upstream_sock;

        // Short timeout for select (10ms)
        var timeout: ws2.timeval = .{ .sec = 0, .usec = 10000 };

        const select_result = ws2.select(0, &read_fds, null, null, &timeout);

        if (select_result == SOCKET_ERROR) {
            const err = ws2.WSAGetLastError();
            log.err("select failed: {}", .{err});
            continue;
        }

        // Check if listen socket has data (client -> proxy)
        if (fdIsSet(listen_sock, &read_fds)) {
            var client_addr: ws2.sockaddr.in = undefined;
            var addr_len: i32 = @sizeOf(ws2.sockaddr.in);

            const recv_len = ws2.recvfrom(
                listen_sock,
                &recv_buf,
                @intCast(recv_buf.len),
                0,
                @ptrCast(&client_addr),
                &addr_len,
            );

            if (recv_len > 0) {
                packet_count += 1;
                const data_len: usize = @intCast(recv_len);
                const data = recv_buf[0..data_len];

                // Save client address for responses
                last_client_addr = client_addr;
                have_client = true;

                // Get client IP for logging
                const ip_bytes: [4]u8 = @bitCast(client_addr.addr);

                log.info("C->S #{d}: {d} bytes from {d}.{d}.{d}.{d}:{d}", .{
                    packet_count,
                    data_len,
                    ip_bytes[0],
                    ip_bytes[1],
                    ip_bytes[2],
                    ip_bytes[3],
                    ws2.ntohs(client_addr.port),
                });

                logQuicPacket(data);

                // Forward to upstream
                const send_len = ws2.sendto(
                    upstream_sock,
                    data.ptr,
                    @intCast(data.len),
                    0,
                    @ptrCast(&upstream_addr),
                    @sizeOf(ws2.sockaddr.in),
                );

                if (send_len == SOCKET_ERROR) {
                    const err = ws2.WSAGetLastError();
                    log.err("sendto upstream failed: {}", .{err});
                }
            }
        }

        // Check if upstream socket has data (server -> proxy -> client)
        if (fdIsSet(upstream_sock, &read_fds)) {
            var server_addr: ws2.sockaddr.in = undefined;
            var addr_len: i32 = @sizeOf(ws2.sockaddr.in);

            const recv_len = ws2.recvfrom(
                upstream_sock,
                &recv_buf,
                @intCast(recv_buf.len),
                0,
                @ptrCast(&server_addr),
                &addr_len,
            );

            if (recv_len > 0 and have_client) {
                packet_count += 1;
                const data_len: usize = @intCast(recv_len);
                const data = recv_buf[0..data_len];

                log.info("S->C #{d}: {d} bytes", .{ packet_count, data_len });

                logQuicPacket(data);

                // Forward to client
                const send_len = ws2.sendto(
                    listen_sock,
                    data.ptr,
                    @intCast(data.len),
                    0,
                    @ptrCast(&last_client_addr),
                    @sizeOf(ws2.sockaddr.in),
                );

                if (send_len == SOCKET_ERROR) {
                    const err = ws2.WSAGetLastError();
                    log.err("sendto client failed: {}", .{err});
                }
            }
        }
    }
}

fn fdIsSet(fd: SOCKET, set: *const ws2.fd_set) bool {
    for (0..set.fd_count) |i| {
        if (set.fd_array[i] == fd) return true;
    }
    return false;
}

fn logQuicPacket(data: []const u8) void {
    if (data.len == 0) return;

    const first_byte = data[0];
    const is_long_header = (first_byte & 0x80) != 0;
    const fixed_bit = (first_byte & 0x40) != 0;

    if (is_long_header and fixed_bit) {
        if (data.len >= 5) {
            const version = std.mem.readInt(u32, data[1..5], .big);
            const pkt_type = (first_byte >> 4) & 0x03;
            const type_str = switch (pkt_type) {
                0 => "Initial",
                1 => "0-RTT",
                2 => "Handshake",
                3 => "Retry",
                else => "Unknown",
            };
            log.info("  QUIC {s} v=0x{X:0>8}", .{ type_str, version });
        }
    } else if (!is_long_header and fixed_bit) {
        log.info("  QUIC Short Header (1-RTT)", .{});
    }

    hexDump(data);
}

fn runTcpWindows(allocator: std.mem.Allocator, listen_port: u16, upstream_host: []const u8, upstream_port: u16) !void {
    // Use the high-level Zig API for TCP since it works on Windows
    const Io = std.Io;
    const net = Io.net;
    const Threaded = Io.Threaded;

    var threaded = Threaded.init(allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded.deinit();

    const io = threaded.io();

    // Parse listen address
    const listen_addr = net.IpAddress{ .ip4 = net.Ip4Address.unspecified(listen_port) };

    // Start listening
    var server = try listen_addr.listen(io, .{
        .reuse_address = true,
    });
    defer server.deinit(io);

    log.info("TCP: Listening on port {d}...", .{listen_port});

    // Accept connections
    while (true) {
        const client_stream = server.accept(io) catch |err| {
            log.err("Accept failed: {}", .{err});
            continue;
        };

        log.info("TCP: Client connected", .{});

        // Handle connection in a new thread
        const thread = std.Thread.spawn(.{}, handleTcpConnection, .{
            allocator,
            client_stream,
            upstream_host,
            upstream_port,
            io,
        }) catch |err| {
            log.err("Failed to spawn thread: {}", .{err});
            client_stream.close(io);
            continue;
        };
        thread.detach();
    }
}

fn handleTcpConnection(
    allocator: std.mem.Allocator,
    client_stream: std.Io.net.Stream,
    upstream_host: []const u8,
    upstream_port: u16,
    io: std.Io,
) void {
    const net = std.Io.net;

    defer client_stream.close(io);

    // Connect to upstream server
    const upstream_addr = net.IpAddress.parse(upstream_host, upstream_port) catch |err| {
        log.err("Failed to parse upstream address: {}", .{err});
        return;
    };

    const upstream_stream = upstream_addr.connect(io, .{ .mode = .stream }) catch |err| {
        log.err("Failed to connect to upstream: {}", .{err});
        return;
    };
    defer upstream_stream.close(io);

    log.info("TCP: Connected to upstream {s}:{d}", .{ upstream_host, upstream_port });

    // Create frame parsers for both directions
    var client_parser = frame.FrameParser.init(allocator);
    defer client_parser.deinit();

    var server_parser = frame.FrameParser.init(allocator);
    defer server_parser.deinit();

    // Create reader buffers
    var client_read_buf: [65536]u8 = undefined;
    var upstream_read_buf: [65536]u8 = undefined;

    var client_reader = client_stream.reader(io, &client_read_buf);
    var upstream_reader = upstream_stream.reader(io, &upstream_read_buf);

    // Simple bidirectional forwarding
    var buf: [4096]u8 = undefined;

    while (true) {
        // Try to read from client
        const client_bytes = client_reader.interface.readSliceShort(&buf) catch |err| {
            log.info("TCP: Client read ended: {}", .{err});
            break;
        };

        if (client_bytes > 0) {
            // Parse and log frames
            client_parser.feed(buf[0..client_bytes]);
            while (client_parser.nextFrame()) |pkt| {
                logPacket("C->S", pkt.id, pkt.payload);
            }

            // Forward to upstream
            var data: [1][]const u8 = .{buf[0..client_bytes]};
            _ = io.vtable.netWrite(io.userdata, upstream_stream.socket.handle, &.{}, &data, 0) catch |err| {
                log.err("TCP: Upstream write error: {}", .{err});
                break;
            };
        }

        // Try to read from upstream
        const upstream_bytes = upstream_reader.interface.readSliceShort(&buf) catch |err| {
            log.info("TCP: Upstream read ended: {}", .{err});
            break;
        };

        if (upstream_bytes > 0) {
            // Parse and log frames
            server_parser.feed(buf[0..upstream_bytes]);
            while (server_parser.nextFrame()) |pkt| {
                logPacket("S->C", pkt.id, pkt.payload);
            }

            // Forward to client
            var data: [1][]const u8 = .{buf[0..upstream_bytes]};
            _ = io.vtable.netWrite(io.userdata, client_stream.socket.handle, &.{}, &data, 0) catch |err| {
                log.err("TCP: Client write error: {}", .{err});
                break;
            };
        }
    }

    log.info("TCP: Connection handler finished", .{});
}

fn parseIpv4(host: []const u8) !u32 {
    var result: u32 = 0;
    var octet: u32 = 0;
    var octet_count: u8 = 0;

    for (host) |c| {
        if (c == '.') {
            if (octet > 255) return error.InvalidAddress;
            result |= octet << @intCast(octet_count * 8);
            octet = 0;
            octet_count += 1;
            if (octet_count > 3) return error.InvalidAddress;
        } else if (c >= '0' and c <= '9') {
            octet = octet * 10 + (c - '0');
        } else {
            return error.InvalidAddress;
        }
    }

    if (octet > 255) return error.InvalidAddress;
    result |= octet << @intCast(octet_count * 8);

    if (octet_count != 3) return error.InvalidAddress;

    return result;
}

fn logPacket(direction: []const u8, packet_id: u32, payload: []const u8) void {
    log.info("{s} ID={d} (0x{X:0>4}) len={d}", .{
        direction,
        packet_id,
        packet_id,
        payload.len,
    });

    if (payload.len > 0) {
        hexDump(payload);
    }
}

fn hexDump(data: []const u8) void {
    const dump_len = @min(data.len, 64);
    var hex_buf: [64 * 3]u8 = undefined;
    var hex_idx: usize = 0;

    for (data[0..dump_len]) |byte| {
        const hex = std.fmt.bufPrint(hex_buf[hex_idx..], "{X:0>2} ", .{byte}) catch break;
        hex_idx += hex.len;
    }

    if (data.len > 64) {
        log.debug("  {s}...", .{hex_buf[0..hex_idx]});
    } else {
        log.debug("  {s}", .{hex_buf[0..hex_idx]});
    }
}
