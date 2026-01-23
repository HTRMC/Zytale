const std = @import("std");
const msquic = @import("msquic.zig");
const frame = @import("../net/packet/frame.zig");
const registry = @import("protocol");
const serializer = @import("../protocol/packets/serializer.zig");

const log = std.log.scoped(.stream);

/// Expected protocol hash from Java server
const EXPECTED_PROTOCOL_HASH = "6708f121966c1c443f4b0eb525b2f81d0a8dc61f5003a692a8fa157e5e02cea9";

/// Connection phase for the protocol state machine
pub const ConnectionPhase = enum {
    initial, // Waiting for Connect packet
    password, // Waiting for PasswordResponse (if password required)
    setup, // Setup phase: sent WorldSettings, waiting for RequestAssets
    loading, // Sending assets and world data
    playing, // Client is fully connected
};

/// Pending send buffer awaiting SEND_COMPLETE callback from MsQuic
/// Heap-allocated so pointers remain stable when other entries are removed
const PendingSend = struct {
    buffer: []u8,
    quic_buffer: msquic.QUIC_BUFFER,
};

/// QUIC Stream handler for Hytale protocol
/// Each stream carries framed packets with the Hytale packet format
pub const Stream = struct {
    handle: msquic.QUIC_HANDLE,
    api: *const msquic.QUIC_API_TABLE,
    allocator: std.mem.Allocator,
    parser: frame.FrameParser,
    connection: ?*anyopaque, // Parent connection context
    send_buffer: std.ArrayList(u8),

    // Track buffers until MsQuic SEND_COMPLETE callback
    // Store pointers to heap-allocated PendingSend so addresses stay stable
    pending_sends: std.ArrayListUnmanaged(*PendingSend),

    // Protocol state
    phase: ConnectionPhase,
    player_uuid: ?[16]u8,
    username: ?[]const u8,

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
            .pending_sends = .empty,
            .phase = .initial,
            .player_uuid = null,
            .username = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free any remaining pending send buffers
        for (self.pending_sends.items) |pending| {
            self.allocator.free(pending.buffer);
            self.allocator.destroy(pending);
        }
        self.pending_sends.deinit(self.allocator);

        self.parser.deinit();
        self.send_buffer.deinit(self.allocator);
        if (self.username) |name| {
            self.allocator.free(name);
        }
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
            defer {
                // Free the owned frame payload
                var mutable_pkt = pkt;
                mutable_pkt.deinit();
            }
            self.handlePacket(pkt);
        }
    }

    /// Process a complete packet frame
    fn handlePacket(self: *Self, pkt: frame.Frame) void {
        const name = registry.getName(pkt.id);
        log.info("Received [{s}] ID={d} len={d} phase={s}", .{ name, pkt.id, pkt.payload.len, @tagName(self.phase) });

        // Route packet to handler based on ID
        switch (pkt.id) {
            registry.Connect.id => self.handleConnect(pkt.payload),
            registry.Disconnect.id => self.handleDisconnect(pkt.payload),
            registry.PasswordResponse.id => self.handlePasswordResponse(pkt.payload),
            registry.RequestAssets.id => self.handleRequestAssets(pkt.payload),
            registry.ViewRadius.id => self.handleViewRadius(pkt.payload),
            registry.PlayerOptions.id => self.handlePlayerOptions(pkt.payload),
            registry.ClientReady.id => self.handleClientReady(pkt.payload),
            registry.ClientMovement.id => self.handleClientMovement(pkt.payload),
            registry.Ping.id => self.handlePing(pkt.payload),
            else => {
                log.debug("Unhandled packet ID={d} ({s})", .{ pkt.id, name });
            },
        }
    }

    fn handleConnect(self: *Self, payload: []const u8) void {
        if (self.phase != .initial) {
            log.warn("Received Connect in wrong phase: {s}", .{@tagName(self.phase)});
            return;
        }

        log.info("Parsing Connect packet, len={d}", .{payload.len});

        // Parse the Connect packet
        const connect = serializer.ConnectPacket.parse(payload) orelse {
            log.err("Failed to parse Connect packet", .{});
            self.sendDisconnect("Protocol error: invalid Connect packet") catch {};
            return;
        };

        // Log parsed data
        const uuid_str = serializer.uuidToString(connect.uuid);
        log.info("Connect from: username={s}, uuid={s}", .{ connect.username, &uuid_str });
        log.info("Protocol hash: {s}", .{connect.protocol_hash});
        if (connect.language) |lang| {
            log.info("Language: {s}", .{lang});
        }

        // Validate protocol hash
        if (!std.mem.eql(u8, connect.protocol_hash, EXPECTED_PROTOCOL_HASH)) {
            log.err("Protocol hash mismatch!", .{});
            log.err("Expected: {s}", .{EXPECTED_PROTOCOL_HASH});
            log.err("Got:      {s}", .{connect.protocol_hash});
            self.sendDisconnect("Incompatible protocol version") catch {};
            return;
        }

        // Store player info
        self.player_uuid = connect.uuid;
        if (self.username) |old| {
            self.allocator.free(old);
        }
        self.username = self.allocator.dupe(u8, connect.username) catch null;

        // Check for identity token (authenticated mode)
        if (connect.identity_token != null) {
            log.info("Client has identity token - authenticated mode not yet supported", .{});
            // For now, treat as development mode
        }

        // Development mode: send ConnectAccept with no password
        log.info("Sending ConnectAccept (no password)", .{});
        self.sendConnectAccept(null) catch |err| {
            log.err("Failed to send ConnectAccept: {}", .{err});
            return;
        };

        // No password required, proceed directly to setup
        self.phase = .setup;
        self.beginSetupPhase() catch |err| {
            log.err("Failed to begin setup phase: {}", .{err});
        };
    }

    fn handleDisconnect(self: *Self, payload: []const u8) void {
        _ = payload;
        log.info("Client sent Disconnect", .{});
        self.shutdown();
    }

    fn handlePasswordResponse(self: *Self, payload: []const u8) void {
        if (self.phase != .password) {
            log.warn("Received PasswordResponse in wrong phase", .{});
            return;
        }

        _ = payload;
        // For now, accept any password (development mode)
        log.info("Accepting password (development mode)", .{});

        self.sendPasswordAccepted() catch |err| {
            log.err("Failed to send PasswordAccepted: {}", .{err});
            return;
        };

        self.phase = .setup;
        self.beginSetupPhase() catch |err| {
            log.err("Failed to begin setup phase: {}", .{err});
        };
    }

    fn handleRequestAssets(self: *Self, payload: []const u8) void {
        if (self.phase != .setup) {
            log.warn("Received RequestAssets in wrong phase: {s}", .{@tagName(self.phase)});
            return;
        }

        _ = payload;
        log.info("Client requesting assets", .{});

        self.phase = .loading;

        // Send asset-related packets (minimal for now)
        // In a full implementation, we'd parse the requested assets and send them

        // Send WorldLoadProgress
        self.sendWorldLoadProgress("Loading world...", 0, 0) catch |err| {
            log.err("Failed to send WorldLoadProgress: {}", .{err});
            return;
        };

        // Send WorldLoadFinished
        self.sendWorldLoadFinished() catch |err| {
            log.err("Failed to send WorldLoadFinished: {}", .{err});
            return;
        };

        log.info("Sent world load packets", .{});
    }

    fn handleViewRadius(_: *Self, payload: []const u8) void {
        if (payload.len < 4) return;
        const radius = std.mem.readInt(i32, payload[0..4], .little);
        log.info("Client view radius: {d} units", .{radius});
    }

    fn handlePlayerOptions(self: *Self, payload: []const u8) void {
        log.info("Received PlayerOptions, len={d}", .{payload.len});

        // This is the final step - client is ready to enter world
        self.phase = .playing;

        // TODO: Add player to universe, spawn entity, etc.
        log.info("Client fully connected!", .{});
    }

    fn handleClientReady(_: *Self, payload: []const u8) void {
        _ = payload;
        log.info("Client is ready to play", .{});
    }

    fn handleClientMovement(_: *Self, payload: []const u8) void {
        _ = payload;
        // ClientMovement is sent frequently, only log at debug level
        log.debug("Client movement", .{});
    }

    fn handlePing(self: *Self, payload: []const u8) void {
        // Respond with Pong
        log.debug("Received Ping, sending Pong", .{});
        self.sendPong(payload) catch |err| {
            log.err("Failed to send Pong: {}", .{err});
        };
    }

    // ============================================
    // Packet sending functions
    // ============================================

    fn sendConnectAccept(self: *Self, password_challenge: ?[]const u8) !void {
        const payload = try serializer.serializeConnectAccept(self.allocator, password_challenge);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.ConnectAccept.id, payload);
        log.info("Sent ConnectAccept", .{});
    }

    fn sendPasswordAccepted(self: *Self) !void {
        const payload = try serializer.serializePasswordAccepted(self.allocator);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.PasswordAccepted.id, payload);
        log.info("Sent PasswordAccepted", .{});
    }

    fn sendWorldSettings(self: *Self, world_height: i32) !void {
        const payload = try serializer.serializeWorldSettings(self.allocator, world_height);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.WorldSettings.id, payload);
        log.info("Sent WorldSettings (height={d})", .{world_height});
    }

    fn sendServerInfo(self: *Self, server_name: []const u8, motd: []const u8, max_players: i32) !void {
        const payload = try serializer.serializeServerInfo(self.allocator, server_name, motd, max_players);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.ServerInfo.id, payload);
        log.info("Sent ServerInfo", .{});
    }

    fn sendWorldLoadProgress(self: *Self, message: []const u8, current: i32, total: i32) !void {
        const payload = try serializer.serializeWorldLoadProgress(self.allocator, message, current, total);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.WorldLoadProgress.id, payload);
        log.info("Sent WorldLoadProgress", .{});
    }

    fn sendWorldLoadFinished(self: *Self) !void {
        const payload = try serializer.serializeWorldLoadFinished(self.allocator);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.WorldLoadFinished.id, payload);
        log.info("Sent WorldLoadFinished", .{});
    }

    fn sendDisconnect(self: *Self, reason: []const u8) !void {
        const payload = try serializer.serializeDisconnect(self.allocator, reason, .Disconnect);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.Disconnect.id, payload);
        log.info("Sent Disconnect: {s}", .{reason});
    }

    /// Begin the setup phase - send WorldSettings and ServerInfo
    fn beginSetupPhase(self: *Self) !void {
        log.info("Beginning setup phase", .{});

        // Send WorldSettings (world height = 320, like Java)
        try self.sendWorldSettings(320);

        // Send ServerInfo
        try self.sendServerInfo("Zytale Server", "A Hytale server replica", 100);

        log.info("Setup packets sent, waiting for RequestAssets", .{});
    }

    /// Send a packet to the client
    /// Buffer lifetime: the encoded frame is kept alive until MsQuic fires SEND_COMPLETE
    pub fn sendPacket(self: *Self, packet_id: u32, payload: []const u8) !void {
        const encoded = try frame.encodeFrame(self.allocator, packet_id, payload);

        // Allocate PendingSend on heap so pointer remains stable
        const pending = self.allocator.create(PendingSend) catch |err| {
            self.allocator.free(encoded);
            return err;
        };
        pending.* = .{
            .buffer = encoded,
            .quic_buffer = .{
                .length = @intCast(encoded.len),
                .buffer = encoded.ptr,
            },
        };

        // Track it in our list
        self.pending_sends.append(self.allocator, pending) catch |err| {
            self.allocator.free(encoded);
            self.allocator.destroy(pending);
            return err;
        };

        // Pass pointer to pending entry as client_context - returned in SEND_COMPLETE
        const status = self.api.stream_send(
            self.handle,
            @ptrCast(&pending.quic_buffer),
            1,
            msquic.QUIC_SEND_FLAG_NONE,
            pending, // client_context: returned in SEND_COMPLETE callback
        );

        if (msquic.QUIC_FAILED(status)) {
            // Failed immediately - clean up
            _ = self.pending_sends.pop();
            self.allocator.free(encoded);
            self.allocator.destroy(pending);
            log.err("Stream send failed: 0x{X:0>8}", .{status});
            return error.SendFailed;
        }

        const name = registry.getName(packet_id);
        log.info("Sent [{s}] ID={d} len={d}", .{ name, packet_id, payload.len });
        // DON'T free here - wait for SEND_COMPLETE callback
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
        _ = self.api.stream_shutdown(
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
            const client_ctx = event.payload.send_complete.client_context;

            if (client_ctx) |ctx| {
                const pending: *PendingSend = @ptrCast(@alignCast(ctx));

                // Free the buffer now that MsQuic is done with it
                stream.allocator.free(pending.buffer);

                // Remove from pending list by finding and swap-removing
                for (stream.pending_sends.items, 0..) |item, i| {
                    if (item == pending) {
                        _ = stream.pending_sends.swapRemove(i);
                        break;
                    }
                }

                // Free the PendingSend struct itself
                stream.allocator.destroy(pending);

                log.debug("SEND_COMPLETE: freed buffer, {d} pending remain", .{stream.pending_sends.items.len});
            }

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

            // NOTE: Don't clean up the stream here!
            // The Connection owns the stream and will clean it up in its SHUTDOWN_COMPLETE handler.
            // Cleaning up here causes double-free crashes.
        },

        else => {
            log.debug("Unhandled stream event: {}", .{event.type});
        },
    }

    return msquic.QUIC_STATUS_SUCCESS;
}
