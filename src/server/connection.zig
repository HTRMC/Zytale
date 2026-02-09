const std = @import("std");
const msquic = @import("msquic.zig");
const Stream = @import("stream.zig").Stream;
const streamCallback = @import("stream.zig").streamCallback;
const frame = @import("../net/packet/frame.zig");
const registry = @import("protocol");
const auth = @import("../auth/auth.zig");

const log = std.log.scoped(.connection);

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io);
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Connection state machine
pub const ConnectionState = enum {
    connecting,
    authenticating,
    authenticated,
    loading,
    playing,
    disconnecting,
};

/// Client connection handler
/// Manages the QUIC connection and associated streams for a single client
pub const Connection = struct {
    handle: msquic.QUIC_HANDLE,
    api: *const msquic.QUIC_API_TABLE,
    configuration: msquic.QUIC_HANDLE,
    allocator: std.mem.Allocator,
    state: ConnectionState,

    // Network IDs
    client_id: u32,

    // Main bidirectional stream for game packets
    main_stream: ?*Stream,

    // Connection metadata
    remote_addr: ?msquic.QUIC_ADDR,
    connected_time: i64,

    // Player info (populated after auth)
    player_uuid: ?[16]u8,
    username: ?[]const u8,

    // Server reference for callbacks
    server_context: ?*anyopaque,

    // Authentication context for Session Service integration
    session_client: ?*auth.SessionServiceClient,
    server_credentials: ?*const auth.ServerCredentials,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        handle: msquic.QUIC_HANDLE,
        api: *const msquic.QUIC_API_TABLE,
        configuration: msquic.QUIC_HANDLE,
        client_id: u32,
    ) Self {
        return .{
            .handle = handle,
            .api = api,
            .configuration = configuration,
            .allocator = allocator,
            .state = .connecting,
            .client_id = client_id,
            .main_stream = null,
            .remote_addr = null,
            .connected_time = getTimestamp(),
            .player_uuid = null,
            .username = null,
            .server_context = null,
            .session_client = null,
            .server_credentials = null,
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
        // Clean up the stream
        if (self.main_stream) |stream| {
            // First deinit the stream's internal resources
            stream.deinit();
            // Then close the MsQuic stream handle
            stream.close();
            // Finally free the stream struct
            self.allocator.destroy(stream);
            self.main_stream = null;
        }

        // Free username if allocated
        if (self.username) |name| {
            self.allocator.free(name);
            self.username = null;
        }
    }

    /// Set the server context for callbacks
    pub fn setServerContext(self: *Self, ctx: ?*anyopaque) void {
        self.server_context = ctx;
    }

    /// Handle a new peer-initiated stream
    pub fn handleNewStream(self: *Self, stream_handle: msquic.QUIC_HANDLE, flags: msquic.QUIC_STREAM_OPEN_FLAGS) !void {
        const is_bidi = (flags & msquic.QUIC_STREAM_OPEN_FLAG_UNIDIRECTIONAL) == 0;

        log.info("New stream from peer (bidirectional={})", .{is_bidi});

        // Create stream wrapper
        const stream = try self.allocator.create(Stream);
        stream.* = Stream.init(self.allocator, stream_handle, self.api);
        stream.setConnectionContext(self);

        // Pass auth context to stream for Session Service integration
        stream.setAuthContext(self.session_client, self.server_credentials);

        // Set the callback handler
        self.api.set_callback_handler(stream_handle, @ptrCast(@constCast(&streamCallback)), stream);

        if (is_bidi and self.main_stream == null) {
            self.main_stream = stream;
            log.info("Set as main stream", .{});
        }
    }

    /// Send ConnectAccept after successful authentication
    pub fn sendConnectAccept(self: *Self) !void {
        const stream = self.main_stream orelse return error.NoMainStream;

        // ConnectAccept packet (ID=14)
        // Format: [1 byte status] + optional data
        var payload: [1]u8 = .{0}; // Success status
        try stream.sendPacket(registry.ConnectAccept.id, &payload);

        log.info("Sent ConnectAccept to client {d}", .{self.client_id});
    }

    /// Send SetClientId to assign network ID
    pub fn sendSetClientId(self: *Self) !void {
        const stream = self.main_stream orelse return error.NoMainStream;

        // SetClientId packet (ID=100)
        // Format: [4 bytes] client_id (u32 LE)
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, self.client_id, .little);
        try stream.sendPacket(registry.SetClientId.id, &payload);

        log.info("Sent SetClientId: {d}", .{self.client_id});
    }

    /// Send ViewRadius to set chunk loading distance
    pub fn sendViewRadius(self: *Self, radius: u32) !void {
        const stream = self.main_stream orelse return error.NoMainStream;

        // ViewRadius packet (ID=32)
        // Format: [4 bytes] radius (u32 LE)
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, radius, .little);
        try stream.sendPacket(registry.ViewRadius.id, &payload);

        log.info("Sent ViewRadius: {d}", .{radius});
    }

    /// Send JoinWorld to transition client to world
    pub fn sendJoinWorld(self: *Self, world_uuid: [16]u8, clear_world: bool, fade: bool) !void {
        const stream = self.main_stream orelse return error.NoMainStream;

        // JoinWorld packet (ID=104)
        // Format: [1 byte] clearWorld, [1 byte] fadeInOut, [16 bytes] worldUuid
        var payload: [18]u8 = undefined;
        payload[0] = if (clear_world) 1 else 0;
        payload[1] = if (fade) 1 else 0;
        @memcpy(payload[2..18], &world_uuid);
        try stream.sendPacket(registry.JoinWorld.id, &payload);

        log.info("Sent JoinWorld", .{});
    }

    /// Send SetGameMode
    pub fn sendSetGameMode(self: *Self, mode: u8) !void {
        const stream = self.main_stream orelse return error.NoMainStream;

        // SetGameMode packet (ID=101)
        // Format: [1 byte] mode (0=survival, 1=creative, etc.)
        var payload: [1]u8 = .{mode};
        try stream.sendPacket(registry.SetGameMode.id, &payload);

        log.info("Sent SetGameMode: {d}", .{mode});
    }

    /// Send SetEntitySeed for entity ID generation
    pub fn sendSetEntitySeed(self: *Self, seed: u32) !void {
        const stream = self.main_stream orelse return error.NoMainStream;

        // SetEntitySeed packet (ID=160)
        // Format: [4 bytes] seed (u32 LE)
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, seed, .little);
        try stream.sendPacket(registry.SetEntitySeed.id, &payload);

        log.info("Sent SetEntitySeed: {d}", .{seed});
    }

    /// Send a raw packet to the client
    pub fn sendPacket(self: *Self, packet_id: u32, payload: []const u8) !void {
        const stream = self.main_stream orelse return error.NoMainStream;
        try stream.sendPacket(packet_id, payload);
    }

    /// Transition to authenticated state and begin world loading
    pub fn onAuthenticated(self: *Self) !void {
        self.state = .authenticated;
        log.info("Client {d} authenticated", .{self.client_id});

        // Begin the join sequence
        try self.sendConnectAccept();
        try self.sendSetClientId();
        try self.sendViewRadius(6); // 6 chunk radius
        try self.sendSetGameMode(1); // Creative mode

        // Generate random entity seed
        var rng = std.Random.DefaultPrng.init(@bitCast(getTimestamp()));
        try self.sendSetEntitySeed(rng.random().int(u32));

        self.state = .loading;
    }

    /// Gracefully disconnect the client
    pub fn disconnect(self: *Self, error_code: u64) void {
        self.state = .disconnecting;
        self.api.connection_shutdown(
            self.handle,
            msquic.QUIC_CONNECTION_SHUTDOWN_FLAG_NONE,
            error_code,
        );
    }

    /// Close the connection handle
    pub fn close(self: *Self) void {
        self.api.connection_close(self.handle);
    }
};

/// Connection callback handler for MsQuic
pub fn connectionCallback(
    connection_handle: msquic.QUIC_HANDLE,
    context: ?*anyopaque,
    event: *msquic.QUIC_CONNECTION_EVENT,
) callconv(.c) msquic.QUIC_STATUS {
    _ = connection_handle;
    const conn: *Connection = @as(?*Connection, @ptrCast(@alignCast(context))) orelse {
        log.err("Connection callback with null context", .{});
        return msquic.QUIC_STATUS_SUCCESS;
    };

    switch (event.type) {
        .CONNECTED => {
            const resumed = event.payload.connected.session_resumed != 0;
            log.info("Connection established (resumed={})", .{resumed});

            conn.state = .authenticating;
        },

        .SHUTDOWN_INITIATED_BY_TRANSPORT => {
            const status = event.payload.shutdown_initiated_by_transport.status;
            const error_code = event.payload.shutdown_initiated_by_transport.error_code;
            log.warn("Transport shutdown: status=0x{X:0>8}, error={d}", .{ status, error_code });
        },

        .SHUTDOWN_INITIATED_BY_PEER => {
            const error_code = event.payload.shutdown_initiated_by_peer.error_code;
            log.info("Peer initiated shutdown: error={d}", .{error_code});
        },

        .SHUTDOWN_COMPLETE => {
            const completed = event.payload.shutdown_complete.handshake_completed != 0;
            log.info("Connection shutdown complete (handshake_completed={})", .{completed});

            // Save allocator before deinit (deinit may clear fields)
            const allocator = conn.allocator;

            // Clean up connection resources first
            conn.deinit();

            // Close the MsQuic handle
            conn.close();

            // Free the connection struct itself
            allocator.destroy(conn);
        },

        .PEER_STREAM_STARTED => {
            const stream_handle = event.payload.peer_stream_started.stream;
            const flags = event.payload.peer_stream_started.flags;

            conn.handleNewStream(stream_handle, flags) catch |err| {
                log.err("Failed to handle new stream: {}", .{err});
                return msquic.QUIC_STATUS_ABORTED;
            };
        },

        .STREAMS_AVAILABLE => {
            const bidi = event.payload.streams_available.bidirectional_count;
            const unidi = event.payload.streams_available.unidirectional_count;
            log.debug("Streams available: bidi={d}, unidi={d}", .{ bidi, unidi });
        },

        .DATAGRAM_RECEIVED => {
            const buffer = event.payload.datagram_received.buffer;
            log.debug("Datagram received: {d} bytes", .{buffer.length});
        },

        else => {
            log.debug("Unhandled connection event: {}", .{event.type});
        },
    }

    return msquic.QUIC_STATUS_SUCCESS;
}
