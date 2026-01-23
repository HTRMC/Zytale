const std = @import("std");
const msquic = @import("msquic.zig");
const wincrypt = @import("wincrypt.zig");
const Connection = @import("connection.zig").Connection;
const connectionCallback = @import("connection.zig").connectionCallback;
const Stream = @import("stream.zig").Stream;
const registry = @import("protocol");

const log = std.log.scoped(.server);

/// Hytale QUIC Server Configuration
pub const ServerConfig = struct {
    /// Port to listen on (default: 5520)
    port: u16 = 5520,

    /// TLS certificate file path (PEM format)
    cert_file: ?[:0]const u8 = null,

    /// TLS private key file path (PEM format)
    key_file: ?[:0]const u8 = null,

    /// Maximum concurrent connections
    max_connections: u32 = 100,

    /// Idle timeout in milliseconds
    idle_timeout_ms: u64 = 30000,

    /// View radius for chunk loading (in chunks)
    view_radius: u32 = 6,

    /// Application-Layer Protocol Negotiation identifier
    alpn: []const u8 = "hytale/1",
};

/// Hytale QUIC Server
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,
    quic: ?msquic.MsQuic,
    api: ?*const msquic.QUIC_API_TABLE,

    // MsQuic handles
    registration: msquic.QUIC_HANDLE,
    configuration: msquic.QUIC_HANDLE,
    listener: msquic.QUIC_HANDLE,

    // Self-signed certificate (generated at runtime)
    cert: ?wincrypt.Certificate,

    // Connection management
    connections: std.AutoHashMap(u32, *Connection),
    next_client_id: u32,
    mutex: std.Thread.Mutex,

    // Server state
    running: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !Self {
        return .{
            .allocator = allocator,
            .config = config,
            .quic = null,
            .api = null,
            .registration = null,
            .configuration = null,
            .listener = null,
            .cert = null,
            .connections = std.AutoHashMap(u32, *Connection).init(allocator),
            .next_client_id = 1,
            .mutex = .{},
            .running = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        // Clean up connections
        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.connections.deinit();

        // Close MsQuic handles
        if (self.api) |api| {
            if (self.listener != null) {
                api.listener_close(self.listener);
            }
            if (self.configuration != null) {
                api.configuration_close(self.configuration);
            }
            if (self.registration != null) {
                api.registration_close(self.registration);
            }
        }

        if (self.quic) |*quic| {
            quic.deinit();
        }

        // Free the self-signed certificate
        if (self.cert) |*cert| {
            cert.deinit();
        }
    }

    /// Initialize MsQuic and configure the server
    pub fn setup(self: *Self) !void {
        log.info("Initializing MsQuic...", .{});

        // Load MsQuic library
        self.quic = try msquic.MsQuic.init(self.allocator);
        self.api = self.quic.?.api;

        const api = self.api.?;

        // Create registration
        const reg_config = msquic.QUIC_REGISTRATION_CONFIG{
            .app_name = "Zytale Hytale Server",
            .execution_profile = .LOW_LATENCY,
        };

        var status = api.registration_open(&reg_config, &self.registration);
        if (msquic.QUIC_FAILED(status)) {
            log.err("Registration open failed: 0x{X:0>8}", .{status});
            return error.RegistrationFailed;
        }

        log.info("Registration opened", .{});

        // Configure QUIC settings
        var settings = msquic.QUIC_SETTINGS{};
        settings.idle_timeout_ms = self.config.idle_timeout_ms;
        settings.is_set.idle_timeout_ms = true;
        settings.peer_bidi_stream_count = 1;
        settings.is_set.peer_bidi_stream_count = true;
        settings.peer_unidi_stream_count = 1;
        settings.is_set.peer_unidi_stream_count = true;

        // Create ALPN buffer (raw protocol name, no length prefix - MsQuic handles that)
        var alpn_data: [256]u8 = undefined;
        @memcpy(alpn_data[0..self.config.alpn.len], self.config.alpn);

        var alpn_buffer = msquic.QUIC_BUFFER{
            .length = @intCast(self.config.alpn.len),
            .buffer = &alpn_data,
        };

        // Open configuration
        status = api.configuration_open(
            self.registration,
            @ptrCast(&alpn_buffer),
            1,
            &settings,
            @sizeOf(msquic.QUIC_SETTINGS),
            null,
            &self.configuration,
        );

        if (msquic.QUIC_FAILED(status)) {
            log.err("Configuration open failed: 0x{X:0>8}", .{status});
            return error.ConfigurationFailed;
        }

        log.info("Configuration opened", .{});

        // Load TLS credentials
        try self.loadCredentials();

        log.info("Server setup complete", .{});
    }

    fn loadCredentials(self: *Self) !void {
        const api = self.api.?;

        // Require client certificate (mutual TLS) like the Java server
        // Also indicate when we receive a certificate for logging
        const cred_flags = msquic.QUIC_CREDENTIAL_FLAG_REQUIRE_CLIENT_AUTHENTICATION |
            msquic.QUIC_CREDENTIAL_FLAG_INDICATE_CERTIFICATE_RECEIVED |
            msquic.QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION; // Accept self-signed client certs

        var cred_config = msquic.QUIC_CREDENTIAL_CONFIG{
            .type = .NONE,
            .flags = cred_flags,
            .certificate = .{ .hash = null },
            .principal = null,
            .reserved = null,
            .async_handler = null,
            .allowed_cipher_suites = msquic.QUIC_ALLOWED_CIPHER_SUITE_NONE,
            .ca_certificate_file = null,
        };

        // If cert/key files provided, use them
        if (self.config.cert_file != null and self.config.key_file != null) {
            var cert_file_config = msquic.QUIC_CERTIFICATE_FILE{
                .certificate_file = self.config.cert_file.?,
                .private_key_file = self.config.key_file.?,
            };

            cred_config.type = .FILE;
            cred_config.certificate.file = &cert_file_config;

            log.info("Loading TLS credentials from files", .{});
        } else {
            // Generate self-signed certificate at runtime (like Java Hytale server)
            self.cert = wincrypt.generateSelfSignedCert(self.allocator, .{
                .subject = "CN=localhost",
                .key_type = .rsa_2048,
                .validity_years = 1,
            }) catch |err| {
                log.err("Failed to generate self-signed certificate: {}", .{err});
                return error.CertificateGenerationFailed;
            };

            cred_config.type = .CONTEXT;
            cred_config.certificate.context = @ptrCast(@constCast(self.cert.?.context));
        }

        const status = api.configuration_load_credential(self.configuration, &cred_config);
        if (msquic.QUIC_FAILED(status)) {
            log.err("Failed to load credentials: 0x{X:0>8}", .{status});
            return error.CredentialLoadFailed;
        }

        log.info("TLS credentials loaded", .{});
    }

    /// Start listening for connections
    pub fn start(self: *Self) !void {
        const api = self.api orelse return error.NotInitialized;

        // Create listener
        var status = api.listener_open(
            self.registration,
            listenerCallback,
            self,
            &self.listener,
        );

        if (msquic.QUIC_FAILED(status)) {
            log.err("Listener open failed: 0x{X:0>8}", .{status});
            return error.ListenerOpenFailed;
        }

        // Set listen address
        var addr: msquic.QUIC_ADDR = undefined;
        addr.setUnspecified(msquic.QUIC_ADDRESS_FAMILY_INET, self.config.port);

        // Create ALPN buffer for listener (raw protocol name, no length prefix)
        var alpn_data: [256]u8 = undefined;
        @memcpy(alpn_data[0..self.config.alpn.len], self.config.alpn);

        var alpn_buffer = msquic.QUIC_BUFFER{
            .length = @intCast(self.config.alpn.len),
            .buffer = &alpn_data,
        };

        // Start listening
        status = api.listener_start(
            self.listener,
            @ptrCast(&alpn_buffer),
            1,
            &addr,
        );

        if (msquic.QUIC_FAILED(status)) {
            log.err("Listener start failed: 0x{X:0>8}", .{status});
            return error.ListenerStartFailed;
        }

        self.running = true;
        log.info("Server listening on port {d}", .{self.config.port});
    }

    /// Stop the server
    pub fn stop(self: *Self) void {
        if (!self.running) return;

        self.running = false;

        if (self.api) |api| {
            if (self.listener != null) {
                api.listener_stop(self.listener);
                log.info("Server stopped", .{});
            }
        }
    }

    /// Handle a new incoming connection
    fn handleNewConnection(self: *Self, info: *const msquic.QUIC_NEW_CONNECTION_INFO, connection_handle: msquic.QUIC_HANDLE) !void {
        const api = self.api orelse return error.NotInitialized;

        // Get remote address for logging
        const remote = info.remote_address;
        const ip = remote.ip.ipv4;
        const ip_bytes: [4]u8 = @bitCast(ip.addr);
        const port = std.mem.bigToNative(u16, ip.port);

        log.info("New connection from {d}.{d}.{d}.{d}:{d}", .{
            ip_bytes[0],
            ip_bytes[1],
            ip_bytes[2],
            ip_bytes[3],
            port,
        });

        // Assign client ID
        self.mutex.lock();
        const client_id = self.next_client_id;
        self.next_client_id += 1;
        self.mutex.unlock();

        // Create connection wrapper
        const conn = try self.allocator.create(Connection);
        conn.* = Connection.init(
            self.allocator,
            connection_handle,
            api,
            self.configuration,
            client_id,
        );
        conn.setServerContext(self);
        conn.remote_addr = remote.*;

        // Register connection
        self.mutex.lock();
        try self.connections.put(client_id, conn);
        self.mutex.unlock();

        // Set callback handler
        api.set_callback_handler(connection_handle, @ptrCast(@constCast(&connectionCallback)), conn);

        // Accept the connection by setting configuration
        const status = api.connection_set_configuration(connection_handle, self.configuration);
        if (msquic.QUIC_FAILED(status)) {
            log.err("Failed to set connection configuration: 0x{X:0>8}", .{status});
            return error.ConfigurationFailed;
        }

        log.info("Accepted connection, assigned client_id={d}", .{client_id});
    }

    /// Get a connection by client ID
    pub fn getConnection(self: *Self, client_id: u32) ?*Connection {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.connections.get(client_id);
    }

    /// Remove a connection
    pub fn removeConnection(self: *Self, client_id: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.connections.remove(client_id);
    }

    /// Get current connection count
    pub fn connectionCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.connections.count();
    }
};

/// Listener callback handler for MsQuic
fn listenerCallback(
    listener: msquic.QUIC_HANDLE,
    context: ?*anyopaque,
    event: *msquic.QUIC_LISTENER_EVENT,
) callconv(.c) msquic.QUIC_STATUS {
    _ = listener;

    log.info("Listener event: {}", .{event.type});

    const srv: *Server = @as(?*Server, @ptrCast(@alignCast(context))) orelse {
        log.err("Listener callback with null context", .{});
        return msquic.QUIC_STATUS_ABORTED;
    };

    switch (event.type) {
        .NEW_CONNECTION => {
            const info = event.payload.new_connection.info;
            const conn_handle = event.payload.new_connection.connection;

            // Log client ALPN for debugging
            if (info.client_alpn_list_length > 0) {
                const alpn_list = info.client_alpn_list[0..info.client_alpn_list_length];
                log.info("Client ALPN list ({d} bytes): {s}", .{ info.client_alpn_list_length, alpn_list });
            }
            if (info.negotiated_alpn_length > 0) {
                const neg_alpn = info.negotiated_alpn[0..info.negotiated_alpn_length];
                log.info("Negotiated ALPN: {s}", .{neg_alpn});
            }

            srv.handleNewConnection(info, conn_handle) catch |err| {
                log.err("Failed to handle new connection: {}", .{err});
                return msquic.QUIC_STATUS_CONNECTION_REFUSED;
            };

            return msquic.QUIC_STATUS_SUCCESS;
        },

        .STOP_COMPLETE => {
            log.info("Listener stopped", .{});
        },
    }

    return msquic.QUIC_STATUS_SUCCESS;
}

/// Run the server (blocking)
pub fn runServer(allocator: std.mem.Allocator, config: ServerConfig) !void {
    var server = try Server.init(allocator, config);
    defer server.deinit();

    try server.setup();
    try server.start();

    log.info("Server running. Press Ctrl+C to stop.", .{});

    // Keep running until interrupted
    const io = std.Io.Threaded.global_single_threaded.io();
    while (server.running) {
        std.Io.sleep(io, std.Io.Duration.fromMilliseconds(100), .awake) catch {};
    }
}

// Re-export for convenience
pub const MsQuic = msquic.MsQuic;
pub const QUIC_STATUS = msquic.QUIC_STATUS;
pub const QUIC_SUCCEEDED = msquic.QUIC_SUCCEEDED;
pub const QUIC_FAILED = msquic.QUIC_FAILED;
