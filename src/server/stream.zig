const std = @import("std");
const msquic = @import("msquic.zig");
const frame = @import("../net/packet/frame.zig");
const registry = @import("protocol");
const serializer = @import("../protocol/packets/serializer.zig");
const zstd = @import("../net/compression/zstd.zig");
const auth = @import("../auth/auth.zig");
const assets = @import("../assets/mod.zig");
const Server = @import("server.zig").Server;
const Connection = @import("connection.zig").Connection;
const JoinSequence = @import("join.zig").JoinSequence;
const World = @import("../world/world.zig").World;
const DebugConfig = @import("config.zig").DebugConfig;

const log = std.log.scoped(.stream);

/// Expected protocol constants from Java server
const EXPECTED_PROTOCOL_CRC: i32 = 1789265863;
const EXPECTED_PROTOCOL_BUILD: i32 = 2;

/// Connection phase for the protocol state machine
pub const ConnectionPhase = enum {
    initial, // Waiting for Connect packet
    awaiting_auth, // Sent AuthGrant, waiting for AuthToken (authenticated mode)
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

    // Authentication context (optional - may be null if server has no credentials)
    session_client: ?*auth.SessionServiceClient,
    server_credentials: ?*const auth.ServerCredentials,

    // Store client's identity token for auth exchange
    client_identity_token: ?[]const u8,

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
            .session_client = null,
            .server_credentials = null,
            .client_identity_token = null,
        };
    }

    /// Set authentication context for Session Service integration
    pub fn setAuthContext(
        self: *Self,
        session_client: ?*auth.SessionServiceClient,
        server_credentials: ?*const auth.ServerCredentials,
    ) void {
        self.session_client = session_client;
        self.server_credentials = server_credentials;
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
        if (self.client_identity_token) |token| {
            self.allocator.free(token);
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
            registry.AuthToken.id => self.handleAuthToken(pkt.payload),
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
        log.info("Protocol CRC: {d}, Build: {d}, Client Version: {s}", .{ connect.protocol_crc, connect.protocol_build_number, connect.client_version });
        if (connect.language) |lang| {
            log.info("Language: {s}", .{lang});
        }

        // Validate protocol CRC and build number
        if (connect.protocol_crc != EXPECTED_PROTOCOL_CRC or connect.protocol_build_number != EXPECTED_PROTOCOL_BUILD) {
            if (connect.protocol_build_number < EXPECTED_PROTOCOL_BUILD) {
                log.err("Client protocol outdated!", .{});
                log.err("Expected build: {d}, Got: {d}", .{ EXPECTED_PROTOCOL_BUILD, connect.protocol_build_number });
                // Error code 5 = client older than server
                self.sendDisconnect("Client outdated - please update") catch {};
            } else {
                log.err("Server protocol outdated!", .{});
                log.err("Expected build: {d}, Got: {d}", .{ EXPECTED_PROTOCOL_BUILD, connect.protocol_build_number });
                // Error code 6 = server older than client
                self.sendDisconnect("Server outdated") catch {};
            }
            return;
        }

        // Store player info
        self.player_uuid = connect.uuid;
        if (self.username) |old| {
            self.allocator.free(old);
        }
        self.username = self.allocator.dupe(u8, connect.username) catch null;

        // Check for identity token (authenticated mode)
        if (connect.identity_token) |client_identity_token| {
            log.info("Client has identity token - using authenticated handshake", .{});

            // Check if we have server credentials for real authentication
            const creds = self.server_credentials;
            const client = self.session_client;

            if (creds != null and creds.?.isValid() and client != null) {
                // Real authentication: call Session Service for auth grant
                log.info("Calling Session Service for auth grant...", .{});

                // Store client's identity token for later use
                self.client_identity_token = self.allocator.dupe(u8, client_identity_token) catch null;

                const auth_grant = client.?.requestAuthGrant(
                    client_identity_token,
                    creds.?.audience,
                    creds.?.session_token.?,
                ) catch |err| {
                    log.err("Failed to get auth grant from Session Service: {}", .{err});
                    self.sendDisconnect("Authentication failed - Session Service error") catch {};
                    return;
                };
                defer self.allocator.free(auth_grant);

                // Send AuthGrant with real tokens
                self.sendAuthGrant(auth_grant, creds.?.identity_token) catch |err| {
                    log.err("Failed to send AuthGrant: {}", .{err});
                    return;
                };
            } else {
                // No server credentials - send AuthGrant with null values
                // This will likely fail on the client side, but allows testing
                log.warn("Server credentials not configured - sending empty AuthGrant", .{});
                log.warn("Set HYTALE_SERVER_SESSION_TOKEN and HYTALE_SERVER_IDENTITY_TOKEN for real auth", .{});

                self.sendAuthGrant(null, null) catch |err| {
                    log.err("Failed to send AuthGrant: {}", .{err});
                    return;
                };
            }

            self.phase = .awaiting_auth;
            return;
        }

        // Development mode (no identity token): send ConnectAccept with no password
        // Note: Real Hytale client will reject this as "development mode not supported"
        log.info("Client has no identity token - using development mode", .{});
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

    fn handleAuthToken(self: *Self, payload: []const u8) void {
        if (self.phase != .awaiting_auth) {
            log.warn("Received AuthToken in wrong phase: {s}", .{@tagName(self.phase)});
            return;
        }

        const auth_token = serializer.AuthTokenPacket.parse(payload) orelse {
            log.err("Failed to parse AuthToken packet", .{});
            self.sendDisconnect("Protocol error: invalid AuthToken") catch {};
            return;
        };

        // Log what we received
        if (auth_token.access_token) |token| {
            log.info("Received AuthToken with access_token len={d}", .{token.len});
        } else {
            log.info("Received AuthToken with no access_token", .{});
        }
        if (auth_token.server_authorization_grant) |grant| {
            log.info("AuthToken has server_authorization_grant len={d}", .{grant.len});
        }

        // Check if we have server credentials for real authentication
        const creds = self.server_credentials;
        const client = self.session_client;

        if (creds != null and creds.?.isValid() and client != null) {
            // Real authentication: exchange auth grant for server access token
            if (auth_token.server_authorization_grant) |server_auth_grant| {
                log.info("Exchanging auth grant for server access token...", .{});

                // Get certificate fingerprint (required for exchange)
                const cert_fp = creds.?.cert_fingerprint orelse {
                    log.err("Server certificate fingerprint not configured", .{});
                    self.sendDisconnect("Server misconfigured - missing certificate fingerprint") catch {};
                    return;
                };

                const server_access_token = client.?.exchangeAuthGrant(
                    server_auth_grant,
                    cert_fp,
                    creds.?.session_token.?,
                ) catch |err| {
                    log.err("Failed to exchange auth grant: {}", .{err});
                    self.sendDisconnect("Authentication failed - token exchange error") catch {};
                    return;
                };
                defer self.allocator.free(server_access_token);

                // Send ServerAuthToken with real access token, no password challenge
                self.sendServerAuthToken(server_access_token, null) catch |err| {
                    log.err("Failed to send ServerAuthToken: {}", .{err});
                    return;
                };
            } else {
                log.warn("AuthToken missing server_authorization_grant - sending empty ServerAuthToken", .{});
                self.sendServerAuthToken(null, null) catch |err| {
                    log.err("Failed to send ServerAuthToken: {}", .{err});
                    return;
                };
            }
        } else {
            // No server credentials - send ServerAuthToken with null values
            // From Java: PasswordPacketHandler.java:66-67 - if passwordChallenge == null, proceeds to setup
            log.warn("No server credentials - sending empty ServerAuthToken", .{});
            self.sendServerAuthToken(null, null) catch |err| {
                log.err("Failed to send ServerAuthToken: {}", .{err});
                return;
            };
        }

        // Proceed to setup phase
        self.phase = .setup;
        self.beginSetupPhase() catch |err| {
            log.err("Failed to begin setup phase: {}", .{err});
        };
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

        // Get the server's asset registry through the connection chain
        const asset_registry = self.getAssetRegistry();
        if (asset_registry) |reg| {
            // Generate and send all asset Update* packets
            self.sendAssetPackets(reg) catch |err| {
                log.err("Failed to send asset packets: {}", .{err});
            };
        } else {
            log.warn("No asset registry available - skipping asset packets", .{});
        }

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

    /// Get the asset registry from the server through the connection chain
    fn getAssetRegistry(self: *Self) ?*assets.AssetRegistry {
        // Get Connection from our context
        const conn_ptr = self.connection orelse return null;
        const conn: *Connection = @ptrCast(@alignCast(conn_ptr));

        // Get Server from Connection's server_context
        const server_ptr = conn.server_context orelse return null;
        const server: *Server = @ptrCast(@alignCast(server_ptr));

        return &server.asset_registry;
    }

    /// Get the world from the server through the connection chain
    fn getWorld(self: *Self) ?*World {
        // Get Connection from our context
        const conn_ptr = self.connection orelse return null;
        const conn: *Connection = @ptrCast(@alignCast(conn_ptr));

        // Get Server from Connection's server_context
        const server_ptr = conn.server_context orelse return null;
        const server: *Server = @ptrCast(@alignCast(server_ptr));

        return server.world;
    }

    /// Send all asset Update* packets to the client
    fn sendAssetPackets(self: *Self, reg: *assets.AssetRegistry) !void {
        log.info("Generating asset packets...", .{});

        var packets = try reg.generateInitPackets();
        defer {
            for (packets.items) |p| {
                self.allocator.free(p.payload);
            }
            packets.deinit(self.allocator);
        }

        log.info("Sending {d} asset packets...", .{packets.items.len});

        var sent_count: usize = 0;
        for (packets.items) |p| {
            self.sendPacket(p.packet_id, p.payload) catch |err| {
                log.err("Failed to send asset packet ID={d}: {}", .{ p.packet_id, err });
                continue;
            };
            sent_count += 1;
        }

        log.info("Sent {d}/{d} asset packets", .{ sent_count, packets.items.len });
    }

    fn handleViewRadius(_: *Self, payload: []const u8) void {
        if (payload.len < 4) return;
        const radius = std.mem.readInt(i32, payload[0..4], .little);
        log.info("Client view radius: {d} units", .{radius});
    }

    fn handlePlayerOptions(self: *Self, payload: []const u8) void {
        log.info("Received PlayerOptions, len={d}", .{payload.len});

        // This signals the client is ready to enter the world
        // Begin the join sequence
        self.phase = .loading;

        // Get the server's world through the connection chain
        const world = self.getWorld();
        if (world == null) {
            log.err("No world available - cannot join player", .{});
            self.sendDisconnect("Server has no world configured") catch {};
            return;
        }

        // Get connection for join sequence
        const conn_ptr = self.connection orelse {
            log.err("No connection context - cannot join player", .{});
            return;
        };
        const conn: *Connection = @ptrCast(@alignCast(conn_ptr));

        // Execute join sequence
        var join_seq = JoinSequence.init(self.allocator, conn, world.?, 6);
        join_seq.execute() catch |err| {
            log.err("Join sequence failed: {}", .{err});
            self.sendDisconnect("Failed to join world") catch {};
            return;
        };

        self.phase = .playing;
        log.info("Join sequence complete - client {} is now playing!", .{conn.client_id});
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

    fn sendAuthGrant(self: *Self, auth_grant: ?[]const u8, server_identity_token: ?[]const u8) !void {
        const payload = try serializer.serializeAuthGrant(self.allocator, auth_grant, server_identity_token);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.AuthGrant.id, payload);
        log.info("Sent AuthGrant", .{});
    }

    fn sendServerAuthToken(self: *Self, server_access_token: ?[]const u8, password_challenge: ?[]const u8) !void {
        const payload = try serializer.serializeServerAuthToken(self.allocator, server_access_token, password_challenge);
        defer self.allocator.free(payload);
        try self.sendPacket(registry.ServerAuthToken.id, payload);
        log.info("Sent ServerAuthToken", .{});
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
    /// Automatically compresses packets that have compressed=true in the registry
    pub fn sendPacket(self: *Self, packet_id: u32, payload: []const u8) !void {
        const debug_cfg = DebugConfig.get();

        // Check if this packet type requires compression
        const packet_info = registry.getById(packet_id);
        const wants_compress = packet_info != null and packet_info.?.compressed;
        const should_compress = wants_compress and !debug_cfg.bypass_compression;

        // Hex dump pre-compression payload if requested
        if (debug_cfg.hex_dump_packets) {
            const name = registry.getName(packet_id);
            const dump_len = @min(payload.len, 128);
            log.warn("HEX [{s}] ID={d} pre-compress ({d} bytes, showing {d}):", .{ name, packet_id, payload.len, dump_len });
            hexDumpLine(payload[0..dump_len]);
        }

        if (wants_compress and debug_cfg.bypass_compression) {
            log.warn("DEBUG: skipping compression for packet {d} ({d} bytes)", .{ packet_id, payload.len });
        }

        // Compress payload if needed
        const final_payload: []u8 = if (should_compress) blk: {
            const compressed = zstd.compress(self.allocator, payload) catch |err| {
                log.err("Failed to compress packet {d}: {}", .{ packet_id, err });
                return error.CompressionFailed;
            };
            log.debug("Compressed packet {d}: {d} -> {d} bytes", .{ packet_id, payload.len, compressed.len });
            break :blk compressed;
        } else blk: {
            // For uncompressed packets, dupe the payload since we manage its lifetime
            break :blk try self.allocator.dupe(u8, payload);
        };

        // Hex dump post-compression payload if requested
        if (debug_cfg.hex_dump_packets and should_compress) {
            const dump_len = @min(final_payload.len, 128);
            log.warn("HEX post-compress ({d} bytes, showing {d}):", .{ final_payload.len, dump_len });
            hexDumpLine(final_payload[0..dump_len]);
        }

        const encoded = frame.encodeFrame(self.allocator, packet_id, final_payload) catch |err| {
            self.allocator.free(final_payload);
            return err;
        };
        self.allocator.free(final_payload); // Free the (possibly compressed) payload copy

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
        const compress_str: []const u8 = if (should_compress) " (compressed)" else "";
        log.info("Sent [{s}] ID={d} len={d}{s}", .{ name, packet_id, payload.len, compress_str });
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

/// Hex-dump a slice in rows of 16 bytes (debug utility).
fn hexDumpLine(data: []const u8) void {
    var offset: usize = 0;
    while (offset < data.len) {
        const end = @min(offset + 16, data.len);
        const row = data[offset..end];
        // Print up to 16 bytes per line
        var hex_buf: [16 * 3]u8 = undefined;
        var hex_len: usize = 0;
        for (row) |b| {
            const hi: u8 = "0123456789abcdef"[b >> 4];
            const lo: u8 = "0123456789abcdef"[b & 0x0f];
            hex_buf[hex_len] = hi;
            hex_buf[hex_len + 1] = lo;
            hex_buf[hex_len + 2] = ' ';
            hex_len += 3;
        }
        log.warn("  {x:0>4}: {s}", .{ offset, hex_buf[0..hex_len] });
        offset = end;
    }
}

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
