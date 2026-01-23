const std = @import("std");
const msquic = @import("msquic.zig");
const frame = @import("../net/packet/frame.zig");
const registry = @import("protocol");

const log = std.log.scoped(.stream);

/// QUIC Stream handler for Hytale protocol
/// Each stream carries framed packets with the Hytale packet format
pub const Stream = struct {
    handle: msquic.QUIC_HANDLE,
    api: *const msquic.QUIC_API_TABLE,
    allocator: std.mem.Allocator,
    parser: frame.FrameParser,
    connection: ?*anyopaque, // Parent connection context
    send_buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        handle: msquic.QUIC_HANDLE,
        api: *const msquic.QUIC_API_TABLE,
    ) Self {
        return .{
            .handle = handle,
            .api = api,
            .allocator = allocator,
            .parser = frame.FrameParser.init(allocator),
            .connection = null,
            .send_buffer = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.deinit();
        self.send_buffer.deinit(self.allocator);
    }

    pub fn setConnectionContext(self: *Self, ctx: ?*anyopaque) void {
        self.connection = ctx;
    }

    /// Handle incoming data on the stream
    pub fn handleReceive(self: *Self, buffers: [*]const msquic.QUIC_BUFFER, count: u32) void {
        // Feed all buffers into the frame parser
        for (0..count) |i| {
            const buf = buffers[i];
            const data = buf.buffer[0..buf.length];
            self.parser.feed(data);
        }

        // Process complete frames
        while (self.parser.nextFrame()) |pkt| {
            self.handlePacket(pkt);
        }
    }

    /// Process a complete packet frame
    fn handlePacket(self: *Self, pkt: frame.Frame) void {
        const name = registry.getName(pkt.id);
        log.info("Received [{s}] ID={d} len={d}", .{ name, pkt.id, pkt.payload.len });

        // Route packet to handler based on ID
        switch (pkt.id) {
            registry.Connect.id => self.handleConnect(pkt.payload),
            registry.AuthGrant.id => self.handleAuthGrant(pkt.payload),
            registry.ClientReady.id => self.handleClientReady(pkt.payload),
            registry.ClientMovement.id => self.handleClientMovement(pkt.payload),
            registry.Ping.id => self.handlePing(pkt.payload),
            else => {
                log.debug("Unhandled packet ID={d} ({s})", .{ pkt.id, name });
            },
        }
    }

    fn handleConnect(self: *Self, payload: []const u8) void {
        _ = self;
        log.info("Client sending Connect packet, len={d}", .{payload.len});
        // Connect packet contains:
        // - Protocol version
        // - Client UUID
        // - Username
        // - Auth token info
        // Response will be handled by connection handler after auth
    }

    fn handleAuthGrant(self: *Self, payload: []const u8) void {
        _ = self;
        log.info("Client sent AuthGrant, len={d}", .{payload.len});
        // AuthGrant contains the authentication token from the client
        // Server should verify and send ConnectAccept
    }

    fn handleClientReady(self: *Self, payload: []const u8) void {
        _ = self;
        log.info("Client is ready, len={d}", .{payload.len});
        // Client has loaded all chunks and is ready to play
    }

    fn handleClientMovement(self: *Self, payload: []const u8) void {
        _ = self;
        // ClientMovement is sent frequently, only log at debug level
        log.debug("Client movement, len={d}", .{payload.len});
    }

    fn handlePing(self: *Self, payload: []const u8) void {
        // Respond with Pong
        log.debug("Received Ping, sending Pong", .{});
        self.sendPong(payload) catch |err| {
            log.err("Failed to send Pong: {}", .{err});
        };
    }

    /// Send a packet to the client
    pub fn sendPacket(self: *Self, packet_id: u32, payload: []const u8) !void {
        const encoded = try frame.encodeFrame(self.allocator, packet_id, payload);
        defer self.allocator.free(encoded);

        var buffer = msquic.QUIC_BUFFER{
            .length = @intCast(encoded.len),
            .buffer = @constCast(encoded.ptr),
        };

        const status = self.api.stream_send(
            self.handle,
            @ptrCast(&buffer),
            1,
            msquic.QUIC_SEND_FLAG_NONE,
            null,
        );

        if (msquic.QUIC_FAILED(status)) {
            log.err("Stream send failed: 0x{X:0>8}", .{status});
            return error.SendFailed;
        }

        const name = registry.getName(packet_id);
        log.debug("Sent [{s}] ID={d} len={d}", .{ name, packet_id, payload.len });
    }

    fn sendPong(self: *Self, ping_payload: []const u8) !void {
        // Pong payload mirrors Ping but is 20 bytes (vs 29)
        var pong_payload: [20]u8 = undefined;
        const copy_len = @min(ping_payload.len, 20);
        @memcpy(pong_payload[0..copy_len], ping_payload[0..copy_len]);
        if (copy_len < 20) {
            @memset(pong_payload[copy_len..], 0);
        }
        try self.sendPacket(registry.Pong.id, &pong_payload);
    }

    /// Complete receive operation
    pub fn completeReceive(self: *Self, length: u64) void {
        self.api.stream_receive_complete(self.handle, length);
    }

    /// Gracefully shutdown the stream
    pub fn shutdown(self: *Self) void {
        self.api.stream_shutdown(
            self.handle,
            msquic.QUIC_STREAM_SHUTDOWN_FLAG_GRACEFUL,
            0,
        );
    }

    /// Close the stream
    pub fn close(self: *Self) void {
        self.api.stream_close(self.handle);
    }
};

/// Stream callback handler for MsQuic
pub fn streamCallback(
    stream_handle: msquic.QUIC_HANDLE,
    context: ?*anyopaque,
    event: *msquic.QUIC_STREAM_EVENT,
) callconv(.c) msquic.QUIC_STATUS {
    _ = stream_handle;
    const stream: *Stream = @as(?*Stream, @ptrCast(@alignCast(context))) orelse {
        log.err("Stream callback with null context", .{});
        return msquic.QUIC_STATUS_SUCCESS;
    };

    switch (event.type) {
        .START_COMPLETE => {
            const status = event.payload.start_complete.status;
            if (msquic.QUIC_SUCCEEDED(status)) {
                log.info("Stream started, ID={d}", .{event.payload.start_complete.id});
            } else {
                log.err("Stream start failed: 0x{X:0>8}", .{status});
            }
        },

        .RECEIVE => {
            const recv = event.payload.receive;
            log.debug("Stream receive: {d} buffers, {d} bytes total", .{
                recv.buffer_count,
                recv.total_buffer_length,
            });

            stream.handleReceive(recv.buffer, recv.buffer_count);

            // Tell MsQuic we've consumed all the data
            stream.completeReceive(recv.total_buffer_length);
        },

        .SEND_COMPLETE => {
            const canceled = event.payload.send_complete.canceled != 0;
            if (canceled) {
                log.warn("Stream send was canceled", .{});
            }
        },

        .PEER_SEND_SHUTDOWN => {
            log.info("Peer finished sending on stream", .{});
        },

        .PEER_SEND_ABORTED => {
            const error_code = event.payload.peer_send_aborted.error_code;
            log.warn("Peer aborted send: error={d}", .{error_code});
        },

        .PEER_RECEIVE_ABORTED => {
            const error_code = event.payload.peer_receive_aborted.error_code;
            log.warn("Peer aborted receive: error={d}", .{error_code});
        },

        .SHUTDOWN_COMPLETE => {
            const conn_shutdown = event.payload.shutdown_complete.connection_shutdown != 0;
            log.info("Stream shutdown complete (connection_shutdown={any})", .{conn_shutdown});

            // Clean up the stream
            stream.deinit();
            stream.close();
        },

        else => {
            log.debug("Unhandled stream event: {}", .{event.type});
        },
    }

    return msquic.QUIC_STATUS_SUCCESS;
}
