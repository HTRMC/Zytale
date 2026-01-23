const std = @import("std");
const builtin = @import("builtin");

/// MsQuic Library Bindings for Zig
/// Windows QUIC implementation via msquic.dll

pub const QUIC_STATUS = u32;
pub const QUIC_HANDLE = ?*anyopaque;

// Status codes
pub const QUIC_STATUS_SUCCESS: QUIC_STATUS = 0;
pub const QUIC_STATUS_PENDING: QUIC_STATUS = 0x703E5;
pub const QUIC_STATUS_ABORTED: QUIC_STATUS = 0x80004004;
pub const QUIC_STATUS_CONNECTION_REFUSED: QUIC_STATUS = 0x800704C9;

pub fn QUIC_SUCCEEDED(status: QUIC_STATUS) bool {
    return @as(i32, @bitCast(status)) >= 0;
}

pub fn QUIC_FAILED(status: QUIC_STATUS) bool {
    return @as(i32, @bitCast(status)) < 0;
}

// Address family
pub const QUIC_ADDRESS_FAMILY = u16;
pub const QUIC_ADDRESS_FAMILY_UNSPEC: QUIC_ADDRESS_FAMILY = 0;
pub const QUIC_ADDRESS_FAMILY_INET: QUIC_ADDRESS_FAMILY = 2;
pub const QUIC_ADDRESS_FAMILY_INET6: QUIC_ADDRESS_FAMILY = 23;

// Execution profile
pub const QUIC_EXECUTION_PROFILE = enum(u32) {
    LOW_LATENCY = 0,
    MAX_THROUGHPUT = 1,
    SCAVENGER = 2,
    REAL_TIME = 3,
};

// Credential type
pub const QUIC_CREDENTIAL_TYPE = enum(u32) {
    NONE = 0,
    HASH = 1,
    HASH_STORE = 2,
    CONTEXT = 3,
    FILE = 4,
    FILE_PROTECTED = 5,
    PKCS12 = 6,
};

// Credential flags
pub const QUIC_CREDENTIAL_FLAGS = u32;
pub const QUIC_CREDENTIAL_FLAG_NONE: QUIC_CREDENTIAL_FLAGS = 0x00000000;
pub const QUIC_CREDENTIAL_FLAG_CLIENT: QUIC_CREDENTIAL_FLAGS = 0x00000001;
pub const QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION: QUIC_CREDENTIAL_FLAGS = 0x00000020;
pub const QUIC_CREDENTIAL_FLAG_INDICATE_CERTIFICATE_RECEIVED: QUIC_CREDENTIAL_FLAGS = 0x00000040;

// Certificate hash
pub const QUIC_CERTIFICATE_HASH = extern struct {
    sha_hash: [20]u8,
};

// Certificate file
pub const QUIC_CERTIFICATE_FILE = extern struct {
    private_key_file: [*:0]const u8,
    certificate_file: [*:0]const u8,
};

// Certificate file protected
pub const QUIC_CERTIFICATE_FILE_PROTECTED = extern struct {
    private_key_file: [*:0]const u8,
    certificate_file: [*:0]const u8,
    private_key_password: [*:0]const u8,
};

// Allowed cipher suite flags
pub const QUIC_ALLOWED_CIPHER_SUITE_FLAGS = u32;
pub const QUIC_ALLOWED_CIPHER_SUITE_NONE: QUIC_ALLOWED_CIPHER_SUITE_FLAGS = 0x0;
pub const QUIC_ALLOWED_CIPHER_SUITE_AES_128_GCM_SHA256: QUIC_ALLOWED_CIPHER_SUITE_FLAGS = 0x1;
pub const QUIC_ALLOWED_CIPHER_SUITE_AES_256_GCM_SHA384: QUIC_ALLOWED_CIPHER_SUITE_FLAGS = 0x2;
pub const QUIC_ALLOWED_CIPHER_SUITE_CHACHA20_POLY1305_SHA256: QUIC_ALLOWED_CIPHER_SUITE_FLAGS = 0x4;

// Credential config
pub const QUIC_CREDENTIAL_CONFIG = extern struct {
    type: QUIC_CREDENTIAL_TYPE,
    flags: QUIC_CREDENTIAL_FLAGS,
    certificate: extern union {
        hash: ?*QUIC_CERTIFICATE_HASH,
        file: ?*QUIC_CERTIFICATE_FILE,
        file_protected: ?*QUIC_CERTIFICATE_FILE_PROTECTED,
        context: ?*anyopaque,
    },
    principal: ?[*:0]const u8,
    reserved: ?*anyopaque,
    async_handler: ?*anyopaque,
    allowed_cipher_suites: QUIC_ALLOWED_CIPHER_SUITE_FLAGS,
    ca_certificate_file: ?[*:0]const u8,
};

// Registration config
pub const QUIC_REGISTRATION_CONFIG = extern struct {
    app_name: [*:0]const u8,
    execution_profile: QUIC_EXECUTION_PROFILE,
};

// Buffer
pub const QUIC_BUFFER = extern struct {
    length: u32,
    buffer: [*]u8,
};

// QUIC Address (sockaddr compatible)
pub const QUIC_ADDR = extern struct {
    ip: extern union {
        ipv4: extern struct {
            family: u16,
            port: u16,
            addr: u32,
            zero: [8]u8,
        },
        ipv6: extern struct {
            family: u16,
            port: u16,
            flowinfo: u32,
            addr: [16]u8,
            scope_id: u32,
        },
    },

    pub fn setIpv4(self: *QUIC_ADDR, port: u16, addr: u32) void {
        self.ip.ipv4.family = QUIC_ADDRESS_FAMILY_INET;
        self.ip.ipv4.port = std.mem.nativeToBig(u16, port);
        self.ip.ipv4.addr = addr;
        self.ip.ipv4.zero = [_]u8{0} ** 8;
    }

    pub fn setUnspecified(self: *QUIC_ADDR, family: QUIC_ADDRESS_FAMILY, port: u16) void {
        if (family == QUIC_ADDRESS_FAMILY_INET) {
            self.ip.ipv4.family = family;
            self.ip.ipv4.port = std.mem.nativeToBig(u16, port);
            self.ip.ipv4.addr = 0;
            self.ip.ipv4.zero = [_]u8{0} ** 8;
        } else {
            self.ip.ipv6.family = family;
            self.ip.ipv6.port = std.mem.nativeToBig(u16, port);
            self.ip.ipv6.flowinfo = 0;
            self.ip.ipv6.addr = [_]u8{0} ** 16;
            self.ip.ipv6.scope_id = 0;
        }
    }
};

// Settings fields present flags
pub const QUIC_SETTINGS_INTERNAL = packed struct {
    max_bytes_per_key: bool = false,
    handshake_idle_timeout_ms: bool = false,
    idle_timeout_ms: bool = false,
    mtu_discovery_search_complete_timeout_us: bool = false,
    tls_client_max_send_buffer: bool = false,
    tls_server_max_send_buffer: bool = false,
    stream_recv_window_default: bool = false,
    stream_recv_buffer_default: bool = false,
    conn_flow_control_window: bool = false,
    max_worker_queue_delay_us: bool = false,
    max_stateless_operations: bool = false,
    initial_window_packets: bool = false,
    send_idle_timeout_ms: bool = false,
    initial_rtt_ms: bool = false,
    max_ack_delay_ms: bool = false,
    disconnect_timeout_ms: bool = false,
    keep_alive_interval_ms: bool = false,
    congestion_control_algorithm: bool = false,
    peer_bidi_stream_count: bool = false,
    peer_unidi_stream_count: bool = false,
    max_binding_stateless_operations: bool = false,
    stateless_operation_expiration_ms: bool = false,
    minimum_mtu: bool = false,
    maximum_mtu: bool = false,
    send_buffering_enabled: bool = false,
    pacing_enabled: bool = false,
    migration_enabled: bool = false,
    datagram_receive_enabled: bool = false,
    server_resumption_level: bool = false,
    greasing_quic_bit_enabled: bool = false,
    ecn_enabled: bool = false,
    max_operations_per_drain: bool = false,
};

// Settings
pub const QUIC_SETTINGS = extern struct {
    is_set: QUIC_SETTINGS_INTERNAL = .{},
    max_bytes_per_key: u64 = 0,
    handshake_idle_timeout_ms: u64 = 0,
    idle_timeout_ms: u64 = 0,
    mtu_discovery_search_complete_timeout_us: u64 = 0,
    tls_client_max_send_buffer: u32 = 0,
    tls_server_max_send_buffer: u32 = 0,
    stream_recv_window_default: u32 = 0,
    stream_recv_buffer_default: u32 = 0,
    conn_flow_control_window: u32 = 0,
    max_worker_queue_delay_us: u32 = 0,
    max_stateless_operations: u32 = 0,
    initial_window_packets: u32 = 0,
    send_idle_timeout_ms: u32 = 0,
    initial_rtt_ms: u32 = 0,
    max_ack_delay_ms: u32 = 0,
    disconnect_timeout_ms: u32 = 0,
    keep_alive_interval_ms: u32 = 0,
    congestion_control_algorithm: u16 = 0,
    peer_bidi_stream_count: u16 = 0,
    peer_unidi_stream_count: u16 = 0,
    max_binding_stateless_operations: u16 = 0,
    stateless_operation_expiration_ms: u16 = 0,
    minimum_mtu: u16 = 0,
    maximum_mtu: u16 = 0,
    _bitfield: u8 = 0,
    max_operations_per_drain: u8 = 0,
    mtu_discovery_missing_probe_count: u8 = 0,
    dest_cid_update_idle_timeout_ms: u32 = 0,
    flags: u64 = 0,
    stream_recv_window_bidi_local_default: u32 = 0,
    stream_recv_window_bidi_remote_default: u32 = 0,
    stream_recv_window_unidi_default: u32 = 0,
};

// Listener event types
pub const QUIC_LISTENER_EVENT_TYPE = enum(u32) {
    NEW_CONNECTION = 0,
    STOP_COMPLETE = 1,
};

// Connection event types
pub const QUIC_CONNECTION_EVENT_TYPE = enum(u32) {
    CONNECTED = 0,
    SHUTDOWN_INITIATED_BY_TRANSPORT = 1,
    SHUTDOWN_INITIATED_BY_PEER = 2,
    SHUTDOWN_COMPLETE = 3,
    LOCAL_ADDRESS_CHANGED = 4,
    PEER_ADDRESS_CHANGED = 5,
    PEER_STREAM_STARTED = 6,
    STREAMS_AVAILABLE = 7,
    PEER_NEEDS_STREAMS = 8,
    IDEAL_PROCESSOR_CHANGED = 9,
    DATAGRAM_STATE_CHANGED = 10,
    DATAGRAM_RECEIVED = 11,
    DATAGRAM_SEND_STATE_CHANGED = 12,
    RESUMED = 13,
    RESUMPTION_TICKET_RECEIVED = 14,
    PEER_CERTIFICATE_RECEIVED = 15,
    RELIABLE_RESET_NEGOTIATED = 16,
    ONE_WAY_DELAY_NEGOTIATED = 17,
};

// Stream event types
pub const QUIC_STREAM_EVENT_TYPE = enum(u32) {
    START_COMPLETE = 0,
    RECEIVE = 1,
    SEND_COMPLETE = 2,
    PEER_SEND_SHUTDOWN = 3,
    PEER_SEND_ABORTED = 4,
    PEER_RECEIVE_ABORTED = 5,
    SEND_SHUTDOWN_COMPLETE = 6,
    SHUTDOWN_COMPLETE = 7,
    IDEAL_SEND_BUFFER_SIZE = 8,
    PEER_ACCEPTED = 9,
    CANCEL_ON_LOSS = 10,
};

// Stream open flags
pub const QUIC_STREAM_OPEN_FLAGS = u32;
pub const QUIC_STREAM_OPEN_FLAG_NONE: QUIC_STREAM_OPEN_FLAGS = 0x0000;
pub const QUIC_STREAM_OPEN_FLAG_UNIDIRECTIONAL: QUIC_STREAM_OPEN_FLAGS = 0x0001;

// Stream start flags
pub const QUIC_STREAM_START_FLAGS = u32;
pub const QUIC_STREAM_START_FLAG_NONE: QUIC_STREAM_START_FLAGS = 0x0000;
pub const QUIC_STREAM_START_FLAG_IMMEDIATE: QUIC_STREAM_START_FLAGS = 0x0001;

// Stream shutdown flags
pub const QUIC_STREAM_SHUTDOWN_FLAGS = u32;
pub const QUIC_STREAM_SHUTDOWN_FLAG_NONE: QUIC_STREAM_SHUTDOWN_FLAGS = 0x0000;
pub const QUIC_STREAM_SHUTDOWN_FLAG_GRACEFUL: QUIC_STREAM_SHUTDOWN_FLAGS = 0x0001;
pub const QUIC_STREAM_SHUTDOWN_FLAG_ABORT_SEND: QUIC_STREAM_SHUTDOWN_FLAGS = 0x0002;
pub const QUIC_STREAM_SHUTDOWN_FLAG_ABORT_RECEIVE: QUIC_STREAM_SHUTDOWN_FLAGS = 0x0004;
pub const QUIC_STREAM_SHUTDOWN_FLAG_ABORT: QUIC_STREAM_SHUTDOWN_FLAGS = 0x0006;

// Send flags
pub const QUIC_SEND_FLAGS = u32;
pub const QUIC_SEND_FLAG_NONE: QUIC_SEND_FLAGS = 0x0000;
pub const QUIC_SEND_FLAG_ALLOW_0_RTT: QUIC_SEND_FLAGS = 0x0001;
pub const QUIC_SEND_FLAG_START: QUIC_SEND_FLAGS = 0x0002;
pub const QUIC_SEND_FLAG_FIN: QUIC_SEND_FLAGS = 0x0004;
pub const QUIC_SEND_FLAG_DGRAM_PRIORITY: QUIC_SEND_FLAGS = 0x0008;

// Connection shutdown flags
pub const QUIC_CONNECTION_SHUTDOWN_FLAGS = u32;
pub const QUIC_CONNECTION_SHUTDOWN_FLAG_NONE: QUIC_CONNECTION_SHUTDOWN_FLAGS = 0x0000;
pub const QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT: QUIC_CONNECTION_SHUTDOWN_FLAGS = 0x0001;

// Server resumption level
pub const QUIC_SERVER_RESUMPTION_LEVEL = enum(u32) {
    NO_RESUME = 0,
    RESUME_ONLY = 1,
    RESUME_AND_ZERORTT = 2,
};

// New connection info
pub const QUIC_NEW_CONNECTION_INFO = extern struct {
    quic_version: u32,
    local_address: *const QUIC_ADDR,
    remote_address: *const QUIC_ADDR,
    crypto_buffer_length: u32,
    client_alpn_list_length: u16,
    server_name_length: u16,
    negotiated_alpn_length: u8,
    crypto_buffer: [*]const u8,
    client_alpn_list: [*]const u8,
    server_name: [*]const u8,
    negotiated_alpn: [*]const u8,
};

// Listener event
pub const QUIC_LISTENER_EVENT = extern struct {
    type: QUIC_LISTENER_EVENT_TYPE,
    payload: extern union {
        new_connection: extern struct {
            info: *const QUIC_NEW_CONNECTION_INFO,
            connection: QUIC_HANDLE,
        },
        stop_complete: extern struct {
            app_close_in_progress: u8,
        },
    },
};

// Connection event
pub const QUIC_CONNECTION_EVENT = extern struct {
    type: QUIC_CONNECTION_EVENT_TYPE,
    payload: extern union {
        connected: extern struct {
            session_resumed: u8,
            session_length: u8,
            session_negotiated_alpn: [*]const u8,
        },
        shutdown_initiated_by_transport: extern struct {
            status: QUIC_STATUS,
            error_code: u64,
        },
        shutdown_initiated_by_peer: extern struct {
            error_code: u64,
        },
        shutdown_complete: extern struct {
            handshake_completed: u8,
            peer_acknowledged_shutdown: u8,
            app_close_in_progress: u8,
        },
        peer_stream_started: extern struct {
            stream: QUIC_HANDLE,
            flags: QUIC_STREAM_OPEN_FLAGS,
        },
        streams_available: extern struct {
            bidirectional_count: u16,
            unidirectional_count: u16,
        },
        datagram_received: extern struct {
            buffer: *const QUIC_BUFFER,
            flags: u32,
        },
        resumed: extern struct {
            resumption_state_length: u16,
            resumption_state: [*]const u8,
        },
        _padding: [64]u8,
    },
};

// Stream event
pub const QUIC_STREAM_EVENT = extern struct {
    type: QUIC_STREAM_EVENT_TYPE,
    payload: extern union {
        start_complete: extern struct {
            status: QUIC_STATUS,
            id: u64,
            peer_accepted: u8,
        },
        receive: extern struct {
            absolute_offset: u64,
            total_buffer_length: u64,
            buffer: [*]const QUIC_BUFFER,
            buffer_count: u32,
            flags: u32,
        },
        send_complete: extern struct {
            canceled: u8,
            client_context: ?*anyopaque,
        },
        peer_send_aborted: extern struct {
            error_code: u64,
        },
        peer_receive_aborted: extern struct {
            error_code: u64,
        },
        shutdown_complete: extern struct {
            connection_shutdown: u8,
            app_close_in_progress: u8,
            connection_close_status: QUIC_STATUS,
            connection_error_code: u64,
        },
        ideal_send_buffer_size: extern struct {
            byte_count: u64,
        },
        _padding: [64]u8,
    },
};

// Callback types
pub const QUIC_LISTENER_CALLBACK = *const fn (
    listener: QUIC_HANDLE,
    context: ?*anyopaque,
    event: *QUIC_LISTENER_EVENT,
) callconv(.c) QUIC_STATUS;

pub const QUIC_CONNECTION_CALLBACK = *const fn (
    connection: QUIC_HANDLE,
    context: ?*anyopaque,
    event: *QUIC_CONNECTION_EVENT,
) callconv(.c) QUIC_STATUS;

pub const QUIC_STREAM_CALLBACK = *const fn (
    stream: QUIC_HANDLE,
    context: ?*anyopaque,
    event: *QUIC_STREAM_EVENT,
) callconv(.c) QUIC_STATUS;

// API function types
const SetContextFn = *const fn (QUIC_HANDLE, ?*anyopaque) callconv(.c) void;
const GetContextFn = *const fn (QUIC_HANDLE) callconv(.c) ?*anyopaque;
const SetCallbackHandlerFn = *const fn (QUIC_HANDLE, ?*anyopaque, ?*anyopaque) callconv(.c) void;

const SetParamFn = *const fn (QUIC_HANDLE, u32, u32, ?*const anyopaque) callconv(.c) QUIC_STATUS;
const GetParamFn = *const fn (QUIC_HANDLE, u32, *u32, ?*anyopaque) callconv(.c) QUIC_STATUS;

const RegistrationOpenFn = *const fn (*const QUIC_REGISTRATION_CONFIG, *QUIC_HANDLE) callconv(.c) QUIC_STATUS;
const RegistrationCloseFn = *const fn (QUIC_HANDLE) callconv(.c) void;
const RegistrationShutdownFn = *const fn (QUIC_HANDLE, QUIC_CONNECTION_SHUTDOWN_FLAGS, u64) callconv(.c) void;

const ConfigurationOpenFn = *const fn (QUIC_HANDLE, [*]const QUIC_BUFFER, u32, ?*const QUIC_SETTINGS, u32, ?*anyopaque, *QUIC_HANDLE) callconv(.c) QUIC_STATUS;
const ConfigurationCloseFn = *const fn (QUIC_HANDLE) callconv(.c) void;
const ConfigurationLoadCredentialFn = *const fn (QUIC_HANDLE, *const QUIC_CREDENTIAL_CONFIG) callconv(.c) QUIC_STATUS;

const ListenerOpenFn = *const fn (QUIC_HANDLE, QUIC_LISTENER_CALLBACK, ?*anyopaque, *QUIC_HANDLE) callconv(.c) QUIC_STATUS;
const ListenerCloseFn = *const fn (QUIC_HANDLE) callconv(.c) void;
const ListenerStartFn = *const fn (QUIC_HANDLE, [*]const QUIC_BUFFER, u32, ?*const QUIC_ADDR) callconv(.c) QUIC_STATUS;
const ListenerStopFn = *const fn (QUIC_HANDLE) callconv(.c) void;

const ConnectionOpenFn = *const fn (QUIC_HANDLE, QUIC_CONNECTION_CALLBACK, ?*anyopaque, *QUIC_HANDLE) callconv(.c) QUIC_STATUS;
const ConnectionCloseFn = *const fn (QUIC_HANDLE) callconv(.c) void;
const ConnectionShutdownFn = *const fn (QUIC_HANDLE, QUIC_CONNECTION_SHUTDOWN_FLAGS, u64) callconv(.c) void;
const ConnectionStartFn = *const fn (QUIC_HANDLE, QUIC_HANDLE, QUIC_ADDRESS_FAMILY, [*:0]const u8, u16) callconv(.c) QUIC_STATUS;
const ConnectionSetConfigurationFn = *const fn (QUIC_HANDLE, QUIC_HANDLE) callconv(.c) QUIC_STATUS;
const ConnectionSendResumptionTicketFn = *const fn (QUIC_HANDLE, u32, u16, [*]const u8) callconv(.c) QUIC_STATUS;

const StreamOpenFn = *const fn (QUIC_HANDLE, QUIC_STREAM_OPEN_FLAGS, QUIC_STREAM_CALLBACK, ?*anyopaque, *QUIC_HANDLE) callconv(.c) QUIC_STATUS;
const StreamCloseFn = *const fn (QUIC_HANDLE) callconv(.c) void;
const StreamStartFn = *const fn (QUIC_HANDLE, QUIC_STREAM_START_FLAGS) callconv(.c) QUIC_STATUS;
const StreamShutdownFn = *const fn (QUIC_HANDLE, QUIC_STREAM_SHUTDOWN_FLAGS, u64) callconv(.c) QUIC_STATUS;
const StreamSendFn = *const fn (QUIC_HANDLE, [*]const QUIC_BUFFER, u32, QUIC_SEND_FLAGS, ?*anyopaque) callconv(.c) QUIC_STATUS;
const StreamReceiveCompleteFn = *const fn (QUIC_HANDLE, u64) callconv(.c) void;
const StreamReceiveSetEnabledFn = *const fn (QUIC_HANDLE, u8) callconv(.c) QUIC_STATUS;

const DatagramSendFn = *const fn (QUIC_HANDLE, [*]const QUIC_BUFFER, u32, QUIC_SEND_FLAGS, ?*anyopaque) callconv(.c) QUIC_STATUS;

// API table
pub const QUIC_API_TABLE = extern struct {
    set_context: SetContextFn,
    get_context: GetContextFn,
    set_callback_handler: SetCallbackHandlerFn,

    set_param: SetParamFn,
    get_param: GetParamFn,

    registration_open: RegistrationOpenFn,
    registration_close: RegistrationCloseFn,
    registration_shutdown: RegistrationShutdownFn,

    configuration_open: ConfigurationOpenFn,
    configuration_close: ConfigurationCloseFn,
    configuration_load_credential: ConfigurationLoadCredentialFn,

    listener_open: ListenerOpenFn,
    listener_close: ListenerCloseFn,
    listener_start: ListenerStartFn,
    listener_stop: ListenerStopFn,

    connection_open: ConnectionOpenFn,
    connection_close: ConnectionCloseFn,
    connection_shutdown: ConnectionShutdownFn,
    connection_start: ConnectionStartFn,
    connection_set_configuration: ConnectionSetConfigurationFn,
    connection_send_resumption_ticket: ConnectionSendResumptionTicketFn,

    stream_open: StreamOpenFn,
    stream_close: StreamCloseFn,
    stream_start: StreamStartFn,
    stream_shutdown: StreamShutdownFn,
    stream_send: StreamSendFn,
    stream_receive_complete: StreamReceiveCompleteFn,
    stream_receive_set_enabled: StreamReceiveSetEnabledFn,

    datagram_send: DatagramSendFn,
};

// MsQuic library wrapper
pub const MsQuic = struct {
    dll: std.DynLib,
    api: *const QUIC_API_TABLE,
    dll_path: ?[]const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Attempts to find msquic.dll in various locations
    /// Returns allocated path string or null to use system PATH
    fn findMsQuicDll(allocator: std.mem.Allocator) ?[]const u8 {
        const io = std.Io.Threaded.global_single_threaded.io();

        // 1. Check MSQUIC_PATH environment variable
        const Environ = std.process.Environ;
        if (Environ.getWindows(.{ .block = {} }, std.unicode.wtf8ToWtf16LeStringLiteral("MSQUIC_PATH"))) |value_w| {
            if (std.unicode.wtf16LeToWtf8Alloc(allocator, value_w)) |path| {
                // Verify the file exists
                if (std.Io.Dir.access(.cwd(), io, path, .{})) |_| {
                    std.log.info("Using MsQuic from MSQUIC_PATH: {s}", .{path});
                    return path;
                } else |_| {
                    allocator.free(path);
                }
            } else |_| {}
        }

        // 2. Search NuGet packages directory
        const nuget_paths = [_][]const u8{
            "packages",
            "../packages",
            "../../packages",
        };
        for (nuget_paths) |pkg_base| {
            if (findNuGetMsQuic(allocator, pkg_base)) |path| {
                std.log.info("Using MsQuic from NuGet packages: {s}", .{path});
                return path;
            }
        }

        // 3. Check current directory
        if (std.Io.Dir.access(.cwd(), io, "msquic.dll", .{})) |_| {
            std.log.info("Using MsQuic from current directory", .{});
            return allocator.dupe(u8, "msquic.dll") catch null;
        } else |_| {}

        // 4. Fall back to system PATH (return null to use default)
        std.log.info("Using MsQuic from system PATH", .{});
        return null;
    }

    /// Search NuGet packages directory for MsQuic
    fn findNuGetMsQuic(allocator: std.mem.Allocator, pkg_base: []const u8) ?[]const u8 {
        const io = std.Io.Threaded.global_single_threaded.io();
        var dir = std.Io.Dir.openDir(.cwd(), io, pkg_base, .{ .iterate = true }) catch return null;
        defer dir.close(io);

        var iter = dir.iterate();
        while (iter.next(io) catch null) |entry| {
            if (entry.kind != .directory) continue;

            // Look for Microsoft.MsQuic.* directories
            if (std.mem.startsWith(u8, entry.name, "Microsoft.MsQuic.") or
                std.mem.startsWith(u8, entry.name, "microsoft.native.quic.msquic."))
            {
                // Construct path to native DLL
                const dll_subpath = "runtimes/win-x64/native/msquic.dll";
                const full_path = std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
                    pkg_base,
                    entry.name,
                    dll_subpath,
                }) catch continue;

                // Verify it exists
                if (std.Io.Dir.access(.cwd(), io, full_path, .{})) |_| {
                    return full_path;
                } else |_| {
                    allocator.free(full_path);
                }
            }
        }

        return null;
    }

    pub fn init(allocator: std.mem.Allocator) !Self {
        const dll_path = findMsQuicDll(allocator);
        errdefer if (dll_path) |p| allocator.free(p);

        const dll_name = dll_path orelse "msquic.dll";

        var dll = std.DynLib.open(dll_name) catch |err| {
            std.log.err("Failed to load msquic.dll. Tried locations:", .{});
            std.log.err("  1. MSQUIC_PATH environment variable", .{});
            std.log.err("  2. packages/Microsoft.MsQuic.*/runtimes/win-x64/native/msquic.dll", .{});
            std.log.err("  3. ./msquic.dll (current directory)", .{});
            std.log.err("  4. System PATH", .{});
            std.log.err("", .{});
            std.log.err("Please install MsQuic from https://github.com/microsoft/msquic/releases", .{});
            std.log.err("Or run: nuget install Microsoft.Native.Quic.MsQuic.Schannel -Version 2.3.5", .{});
            return err;
        };
        errdefer dll.close();

        const MsQuicOpenVersionFn = *const fn (u32, **const QUIC_API_TABLE) callconv(.c) QUIC_STATUS;

        const open_fn = dll.lookup(MsQuicOpenVersionFn, "MsQuicOpenVersion") orelse {
            std.log.err("Failed to find MsQuicOpenVersion in msquic.dll", .{});
            return error.SymbolNotFound;
        };

        var api: *const QUIC_API_TABLE = undefined;
        const status = open_fn(2, &api); // Version 2

        if (QUIC_FAILED(status)) {
            std.log.err("MsQuicOpenVersion failed with status: 0x{X:0>8}", .{status});
            return error.MsQuicOpenFailed;
        }

        return Self{
            .dll = dll,
            .api = api,
            .dll_path = dll_path,
            .allocator = allocator,
        };
    }

    /// Legacy init for compatibility (uses page allocator)
    pub fn initLegacy() !Self {
        return init(std.heap.page_allocator);
    }

    pub fn deinit(self: *Self) void {
        const MsQuicCloseFn = *const fn (*const QUIC_API_TABLE) callconv(.c) void;

        if (self.dll.lookup(MsQuicCloseFn, "MsQuicClose")) |close_fn| {
            close_fn(self.api);
        }
        self.dll.close();

        if (self.dll_path) |path| {
            self.allocator.free(path);
        }
    }
};

// Helper to create ALPN buffer
pub fn makeAlpn(comptime alpn: []const u8) QUIC_BUFFER {
    const alpn_with_len = [_]u8{alpn.len} ++ alpn.*;
    return .{
        .length = alpn_with_len.len,
        .buffer = @constCast(&alpn_with_len),
    };
}

// ALPN for Hytale protocol
pub const HYTALE_ALPN = "hytale/1";

test "msquic status helpers" {
    try std.testing.expect(QUIC_SUCCEEDED(QUIC_STATUS_SUCCESS));
    try std.testing.expect(!QUIC_FAILED(QUIC_STATUS_SUCCESS));
    try std.testing.expect(QUIC_FAILED(QUIC_STATUS_ABORTED));
}
