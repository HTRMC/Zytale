// QUIC Server implementation using MsQuic
const std = @import("std");
const msquic = @import("msquic.zig");

const log = std.log.scoped(.quic_server);

pub const QuicServer = struct {
    allocator: std.mem.Allocator,
    quic: ?msquic.MsQuic,
    registration: msquic.HQUIC,
    configuration: msquic.HQUIC,
    listener: msquic.HQUIC,
    alpn: []const u8,
    port: u16,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .quic = null,
            .registration = null,
            .configuration = null,
            .listener = null,
            .alpn = "hytale/1",
            .port = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.quic) |*q| {
            if (self.listener != null) {
                q.listenerClose(self.listener);
            }
            if (self.configuration != null) {
                q.configurationClose(self.configuration);
            }
            if (self.registration != null) {
                q.registrationClose(self.registration);
            }
            q.close();
        }
    }

    pub fn configure(self: *Self, cert_file: [:0]const u8, key_file: [:0]const u8) !void {
        // Open MsQuic
        self.quic = try msquic.MsQuic.open();
        var q = &self.quic.?;

        log.info("MsQuic opened successfully", .{});

        // Create registration
        const reg_config = msquic.QUIC_REGISTRATION_CONFIG{
            .AppName = "Zytale",
            .ExecutionProfile = .LOW_LATENCY,
        };
        self.registration = try q.registrationOpen(&reg_config);
        log.info("Registration opened", .{});

        // Create ALPN buffer
        var alpn_buffer = [_]msquic.QUIC_BUFFER{.{
            .Length = @intCast(self.alpn.len),
            .Buffer = @constCast(@ptrCast(self.alpn.ptr)),
        }};

        // Create settings
        var settings: msquic.QUIC_SETTINGS = .{};
        settings.IdleTimeoutMs = 30000;
        settings.IsSetFlags |= msquic.QUIC_SETTINGS.IDLE_TIMEOUT_MS;
        settings.ServerResumptionLevel = 2; // QUIC_SERVER_RESUME_AND_ZERORTT
        settings.IsSetFlags |= msquic.QUIC_SETTINGS.SERVER_RESUMPTION_LEVEL;
        settings.PeerBidiStreamCount = 100;
        settings.IsSetFlags |= msquic.QUIC_SETTINGS.PEER_BIDI_STREAM_COUNT;

        // Create configuration
        self.configuration = try q.configurationOpen(self.registration, &alpn_buffer, &settings);
        log.info("Configuration opened", .{});

        // Load certificate
        var cert_file_config = msquic.QUIC_CERTIFICATE_FILE{
            .CertificateFile = cert_file.ptr,
            .PrivateKeyFile = key_file.ptr,
        };

        var cred_config: msquic.QUIC_CREDENTIAL_CONFIG = std.mem.zeroes(msquic.QUIC_CREDENTIAL_CONFIG);
        cred_config.Type = .CERTIFICATE_FILE;
        cred_config.Flags = msquic.QUIC_CREDENTIAL_FLAG_NONE;
        cred_config.CertificateFile = &cert_file_config;

        try q.configurationLoadCredential(self.configuration, &cred_config);
        log.info("Certificate loaded from {s}", .{cert_file});
    }

    pub fn start(self: *Self, port: u16) !void {
        self.port = port;
        var q = &self.quic.?;

        // Create listener
        self.listener = try q.listenerOpen(self.registration, listenerCallback, @ptrCast(self));
        log.info("Listener opened", .{});

        // Create ALPN buffer for listener
        var alpn_buffer = [_]msquic.QUIC_BUFFER{.{
            .Length = @intCast(self.alpn.len),
            .Buffer = @constCast(@ptrCast(self.alpn.ptr)),
        }};

        // Create address - bind to all interfaces
        var addr: msquic.QUIC_ADDR = std.mem.zeroes(msquic.QUIC_ADDR);
        addr.Ipv4.sin_family = 2; // AF_INET
        addr.Ipv4.sin_port = std.mem.nativeToBig(u16, port);
        addr.Ipv4.sin_addr.S_un.S_addr = 0; // INADDR_ANY

        try q.listenerStart(self.listener, &alpn_buffer, &addr);
        log.info("QUIC server listening on port {d}", .{port});
    }

    pub fn stop(self: *Self) void {
        if (self.quic) |*q| {
            if (self.listener != null) {
                q.listenerStop(self.listener);
                log.info("Listener stopped", .{});
            }
        }
    }

    fn listenerCallback(
        listener: msquic.HQUIC,
        context: ?*anyopaque,
        event: *msquic.QUIC_LISTENER_EVENT,
    ) callconv(.c) msquic.QUIC_STATUS {
        _ = listener;
        const self: *Self = @ptrCast(@alignCast(context));

        switch (event.Type) {
            .NEW_CONNECTION => {
                log.info("New QUIC connection!", .{});

                const conn_handle = event.payload.NEW_CONNECTION.Connection;

                // Create connection wrapper
                const conn = self.allocator.create(QuicConnection) catch {
                    log.err("Failed to allocate connection", .{});
                    return 0x80004005; // E_FAIL
                };
                conn.* = QuicConnection.init(self.allocator, &self.quic.?, conn_handle, self.configuration);

                // Set callback handler for the connection
                self.quic.?.setCallbackHandler(conn_handle, connectionCallback, @ptrCast(conn));

                // Set configuration on the connection
                self.quic.?.connectionSetConfiguration(conn_handle, self.configuration) catch {
                    log.err("Failed to set connection configuration", .{});
                    self.allocator.destroy(conn);
                    return 0x80004005;
                };

                return msquic.QUIC_STATUS_SUCCESS;
            },
            .STOP_COMPLETE => {
                log.info("Listener stop complete", .{});
                return msquic.QUIC_STATUS_SUCCESS;
            },
        }
    }

    fn connectionCallback(
        connection: msquic.HQUIC,
        context: ?*anyopaque,
        event: *msquic.QUIC_CONNECTION_EVENT,
    ) callconv(.c) msquic.QUIC_STATUS {
        const conn: *QuicConnection = @ptrCast(@alignCast(context));
        _ = connection;

        switch (event.Type) {
            .CONNECTED => {
                log.info("Connection established!", .{});
                conn.connected = true;
                return msquic.QUIC_STATUS_SUCCESS;
            },
            .SHUTDOWN_INITIATED_BY_TRANSPORT => {
                const status = event.payload.SHUTDOWN_INITIATED_BY_TRANSPORT.Status;
                log.info("Connection shutdown by transport: 0x{X}", .{status});
                return msquic.QUIC_STATUS_SUCCESS;
            },
            .SHUTDOWN_INITIATED_BY_PEER => {
                log.info("Connection shutdown by peer", .{});
                return msquic.QUIC_STATUS_SUCCESS;
            },
            .SHUTDOWN_COMPLETE => {
                log.info("Connection shutdown complete", .{});
                conn.closed = true;
                return msquic.QUIC_STATUS_SUCCESS;
            },
            .PEER_STREAM_STARTED => {
                log.info("Peer started a stream", .{});
                const stream = event.payload.PEER_STREAM_STARTED.Stream;

                // Set stream callback
                conn.quic.setCallbackHandler(stream, streamCallback, @ptrCast(conn));

                return msquic.QUIC_STATUS_SUCCESS;
            },
            else => {
                return msquic.QUIC_STATUS_SUCCESS;
            },
        }
    }

    fn streamCallback(
        stream: msquic.HQUIC,
        context: ?*anyopaque,
        event: *msquic.QUIC_STREAM_EVENT,
    ) callconv(.c) msquic.QUIC_STATUS {
        const conn: *QuicConnection = @ptrCast(@alignCast(context));
        _ = stream;

        switch (event.Type) {
            .RECEIVE => {
                const receive = &event.payload.RECEIVE;
                const buf_count = receive.BufferCount;

                var total_len: usize = 0;
                for (0..buf_count) |i| {
                    total_len += receive.Buffers[i].Length;
                }

                log.info("Stream received {d} bytes", .{total_len});

                // Copy data and log
                if (total_len > 0) {
                    const data = conn.allocator.alloc(u8, total_len) catch {
                        return msquic.QUIC_STATUS_SUCCESS;
                    };
                    defer conn.allocator.free(data);

                    var offset: usize = 0;
                    for (0..buf_count) |i| {
                        const buf = receive.Buffers[i];
                        const len = buf.Length;
                        @memcpy(data[offset .. offset + len], buf.Buffer[0..len]);
                        offset += len;
                    }

                    // Log the packet data
                    logPacketData(data);
                }

                return msquic.QUIC_STATUS_SUCCESS;
            },
            .PEER_SEND_SHUTDOWN => {
                log.info("Stream: peer send shutdown", .{});
                return msquic.QUIC_STATUS_SUCCESS;
            },
            .SHUTDOWN_COMPLETE => {
                log.info("Stream shutdown complete", .{});
                return msquic.QUIC_STATUS_SUCCESS;
            },
            else => {
                return msquic.QUIC_STATUS_SUCCESS;
            },
        }
    }

    fn logPacketData(data: []const u8) void {
        if (data.len < 8) {
            log.info("Packet too small: {d} bytes", .{data.len});
            return;
        }

        // Parse Hytale packet frame: [4 bytes len][4 bytes id][payload]
        const payload_len = std.mem.readInt(u32, data[0..4], .little);
        const packet_id = std.mem.readInt(u32, data[4..8], .little);

        log.info("Packet ID={d} (0x{X:0>4}) payload_len={d}", .{ packet_id, packet_id, payload_len });

        // Hex dump first 64 bytes
        const dump_len = @min(data.len, 64);
        var hex_buf: [64 * 3]u8 = undefined;
        var hex_idx: usize = 0;

        for (data[0..dump_len]) |byte| {
            const hex = std.fmt.bufPrint(hex_buf[hex_idx..], "{X:0>2} ", .{byte}) catch break;
            hex_idx += hex.len;
        }

        log.debug("  {s}", .{hex_buf[0..hex_idx]});
    }
};

pub const QuicConnection = struct {
    allocator: std.mem.Allocator,
    quic: *msquic.MsQuic,
    handle: msquic.HQUIC,
    configuration: msquic.HQUIC,
    connected: bool,
    closed: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, quic: *msquic.MsQuic, handle: msquic.HQUIC, configuration: msquic.HQUIC) Self {
        return Self{
            .allocator = allocator,
            .quic = quic,
            .handle = handle,
            .configuration = configuration,
            .connected = false,
            .closed = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.closed) {
            self.quic.connectionClose(self.handle);
        }
    }

    pub fn isConnected(self: *Self) bool {
        return self.connected and !self.closed;
    }

    pub fn shutdown(self: *Self, error_code: u64) void {
        self.quic.connectionShutdown(self.handle, msquic.QUIC_CONNECTION_SHUTDOWN_FLAG_NONE, error_code);
    }
};
