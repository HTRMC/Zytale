// MsQuic C API bindings for Zig - Manual definitions
// https://github.com/microsoft/msquic
const std = @import("std");

// Handle type
pub const HQUIC = ?*anyopaque;

// Status type
pub const QUIC_STATUS = u32;
pub const QUIC_STATUS_SUCCESS: QUIC_STATUS = 0;
pub const QUIC_STATUS_PENDING: QUIC_STATUS = 0x703E5;

pub fn QUIC_FAILED(status: QUIC_STATUS) bool {
    return (@as(i32, @bitCast(status))) < 0;
}

pub fn QUIC_SUCCEEDED(status: QUIC_STATUS) bool {
    return !QUIC_FAILED(status);
}

// Execution profile
pub const QUIC_EXECUTION_PROFILE = enum(u32) {
    LOW_LATENCY = 0,
    MAX_THROUGHPUT = 1,
    SCAVENGER = 2,
    REAL_TIME = 3,
};

// Registration config
pub const QUIC_REGISTRATION_CONFIG = extern struct {
    AppName: [*:0]const u8,
    ExecutionProfile: QUIC_EXECUTION_PROFILE,
};

// Buffer
pub const QUIC_BUFFER = extern struct {
    Length: u32,
    Buffer: [*]u8,
};

// Address (simplified - just enough for IPv4)
pub const QUIC_ADDR = extern struct {
    Ipv4: extern struct {
        sin_family: u16,
        sin_port: u16,
        sin_addr: extern struct {
            S_un: extern struct {
                S_addr: u32,
            },
        },
        sin_zero: [8]u8 = [_]u8{0} ** 8,
    },
};

// Credential types
pub const QUIC_CREDENTIAL_TYPE = enum(u32) {
    NONE = 0,
    CERTIFICATE_HASH = 1,
    CERTIFICATE_HASH_STORE = 2,
    CERTIFICATE_CONTEXT = 3,
    CERTIFICATE_FILE = 4,
    CERTIFICATE_FILE_PROTECTED = 5,
    CERTIFICATE_PKCS12 = 6,
};

// Credential flags
pub const QUIC_CREDENTIAL_FLAG_NONE: u32 = 0x00000000;
pub const QUIC_CREDENTIAL_FLAG_CLIENT: u32 = 0x00000001;
pub const QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION: u32 = 0x00000004;

// Certificate file
pub const QUIC_CERTIFICATE_FILE = extern struct {
    PrivateKeyFile: [*:0]const u8,
    CertificateFile: [*:0]const u8,
};

// Credential config
pub const QUIC_CREDENTIAL_CONFIG = extern struct {
    Type: QUIC_CREDENTIAL_TYPE,
    Flags: u32,
    CertificateFile: ?*QUIC_CERTIFICATE_FILE,
    Principal: ?[*:0]const u8,
    Reserved: ?*anyopaque,
    AsyncHandler: ?*anyopaque,
    AllowedCipherSuites: u32,
    CaCertificateFile: ?[*:0]const u8,
};

// Settings - using a bitfield for IsSet
pub const QUIC_SETTINGS = extern struct {
    IsSetFlags: u64 = 0,
    MaxBytesPerKey: u64 = 0,
    HandshakeIdleTimeoutMs: u64 = 0,
    IdleTimeoutMs: u64 = 0,
    MtuDiscoverySearchCompleteTimeoutUs: u64 = 0,
    TlsClientMaxSendBuffer: u32 = 0,
    TlsServerMaxSendBuffer: u32 = 0,
    StreamRecvWindowDefault: u32 = 0,
    StreamRecvBufferDefault: u32 = 0,
    ConnFlowControlWindow: u32 = 0,
    MaxWorkerQueueDelayUs: u32 = 0,
    MaxStatelessOperations: u32 = 0,
    InitialWindowPackets: u32 = 0,
    SendIdleTimeoutMs: u32 = 0,
    InitialRttMs: u32 = 0,
    MaxAckDelayMs: u32 = 0,
    DisconnectTimeoutMs: u32 = 0,
    KeepAliveIntervalMs: u32 = 0,
    CongestionControlAlgorithm: u16 = 0,
    PeerBidiStreamCount: u16 = 0,
    PeerUnidiStreamCount: u16 = 0,
    MaxBindingStatelessOperations: u16 = 0,
    StatelessOperationExpirationMs: u16 = 0,
    MinimumMtu: u16 = 0,
    MaximumMtu: u16 = 0,
    SendBufferingEnabled: u8 = 0,
    PacingEnabled: u8 = 0,
    MigrationEnabled: u8 = 0,
    DatagramReceiveEnabled: u8 = 0,
    ServerResumptionLevel: u8 = 0,
    _padding: [3]u8 = [_]u8{0} ** 3,

    // Bit positions for IsSetFlags
    pub const IDLE_TIMEOUT_MS: u64 = 1 << 3;
    pub const SERVER_RESUMPTION_LEVEL: u64 = 1 << 21;
    pub const PEER_BIDI_STREAM_COUNT: u64 = 1 << 19;
};

// Event types
pub const QUIC_LISTENER_EVENT_TYPE = enum(u32) {
    NEW_CONNECTION = 0,
    STOP_COMPLETE = 1,
};

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
};

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
};

// Event structures
pub const QUIC_NEW_CONNECTION_INFO = extern struct {
    QuicVersion: u32,
    LocalAddress: ?*anyopaque,
    RemoteAddress: ?*anyopaque,
    CryptoBufferLength: u32,
    ClientAlpnListLength: u16,
    ServerNameLength: u16,
    NegotiatedAlpnLength: u8,
    CryptoBuffer: ?[*]const u8,
    ClientAlpnList: ?[*]const u8,
    NegotiatedAlpn: ?[*]const u8,
    ServerName: ?[*]const u8,
};

pub const QUIC_LISTENER_EVENT = extern struct {
    Type: QUIC_LISTENER_EVENT_TYPE,
    payload: extern union {
        NEW_CONNECTION: extern struct {
            Info: ?*const QUIC_NEW_CONNECTION_INFO,
            Connection: HQUIC,
        },
        STOP_COMPLETE: extern struct {
            AppCloseInProgress: u8,
        },
    },
};

pub const QUIC_CONNECTION_EVENT = extern struct {
    Type: QUIC_CONNECTION_EVENT_TYPE,
    payload: extern union {
        CONNECTED: extern struct {
            SessionResumed: u8,
            NegotiatedAlpnLength: u8,
            NegotiatedAlpn: ?[*]const u8,
        },
        SHUTDOWN_INITIATED_BY_TRANSPORT: extern struct {
            Status: QUIC_STATUS,
            ErrorCode: u64,
        },
        SHUTDOWN_INITIATED_BY_PEER: extern struct {
            ErrorCode: u64,
        },
        SHUTDOWN_COMPLETE: extern struct {
            HandshakeCompleted: u8,
            PeerAcknowledgedShutdown: u8,
            AppCloseInProgress: u8,
        },
        PEER_STREAM_STARTED: extern struct {
            Stream: HQUIC,
            Flags: u32,
        },
        STREAMS_AVAILABLE: extern struct {
            BidirectionalCount: u16,
            UnidirectionalCount: u16,
        },
        _padding: [64]u8,
    },
};

pub const QUIC_STREAM_EVENT = extern struct {
    Type: QUIC_STREAM_EVENT_TYPE,
    payload: extern union {
        RECEIVE: extern struct {
            AbsoluteOffset: u64,
            TotalBufferLength: u64,
            Buffers: [*]const QUIC_BUFFER,
            BufferCount: u32,
            Flags: u32,
        },
        SEND_COMPLETE: extern struct {
            Canceled: u8,
            ClientContext: ?*anyopaque,
        },
        PEER_SEND_ABORTED: extern struct {
            ErrorCode: u64,
        },
        PEER_RECEIVE_ABORTED: extern struct {
            ErrorCode: u64,
        },
        SHUTDOWN_COMPLETE: extern struct {
            ConnectionShutdown: u8,
            AppCloseInProgress: u8,
            ConnectionShutdownByApp: u8,
            ConnectionClosedRemotely: u8,
            ConnectionErrorCode: u64,
            ConnectionCloseStatus: QUIC_STATUS,
        },
        _padding: [64]u8,
    },
};

// Callback function types
pub const QUIC_LISTENER_CALLBACK_FN = *const fn (HQUIC, ?*anyopaque, *QUIC_LISTENER_EVENT) callconv(.c) QUIC_STATUS;
pub const QUIC_CONNECTION_CALLBACK_FN = *const fn (HQUIC, ?*anyopaque, *QUIC_CONNECTION_EVENT) callconv(.c) QUIC_STATUS;
pub const QUIC_STREAM_CALLBACK_FN = *const fn (HQUIC, ?*anyopaque, *QUIC_STREAM_EVENT) callconv(.c) QUIC_STATUS;

// API table
pub const QUIC_API_TABLE = extern struct {
    SetContext: *const fn (HQUIC, ?*anyopaque) callconv(.c) void,
    GetContext: *const fn (HQUIC) callconv(.c) ?*anyopaque,
    SetCallbackHandler: *const fn (HQUIC, ?*anyopaque, ?*anyopaque) callconv(.c) void,
    SetParam: *const fn (HQUIC, u32, u32, ?*const anyopaque) callconv(.c) QUIC_STATUS,
    GetParam: *const fn (HQUIC, u32, *u32, ?*anyopaque) callconv(.c) QUIC_STATUS,
    RegistrationOpen: *const fn (*const QUIC_REGISTRATION_CONFIG, *HQUIC) callconv(.c) QUIC_STATUS,
    RegistrationClose: *const fn (HQUIC) callconv(.c) void,
    RegistrationShutdown: *const fn (HQUIC, u32, u64) callconv(.c) void,
    ConfigurationOpen: *const fn (HQUIC, [*]const QUIC_BUFFER, u32, ?*const QUIC_SETTINGS, u32, ?*anyopaque, *HQUIC) callconv(.c) QUIC_STATUS,
    ConfigurationClose: *const fn (HQUIC) callconv(.c) void,
    ConfigurationLoadCredential: *const fn (HQUIC, *const QUIC_CREDENTIAL_CONFIG) callconv(.c) QUIC_STATUS,
    ListenerOpen: *const fn (HQUIC, QUIC_LISTENER_CALLBACK_FN, ?*anyopaque, *HQUIC) callconv(.c) QUIC_STATUS,
    ListenerClose: *const fn (HQUIC) callconv(.c) void,
    ListenerStart: *const fn (HQUIC, [*]const QUIC_BUFFER, u32, ?*const QUIC_ADDR) callconv(.c) QUIC_STATUS,
    ListenerStop: *const fn (HQUIC) callconv(.c) void,
    ConnectionOpen: *const fn (HQUIC, QUIC_CONNECTION_CALLBACK_FN, ?*anyopaque, *HQUIC) callconv(.c) QUIC_STATUS,
    ConnectionClose: *const fn (HQUIC) callconv(.c) void,
    ConnectionShutdown: *const fn (HQUIC, u32, u64) callconv(.c) void,
    ConnectionStart: *const fn (HQUIC, HQUIC, u16, [*:0]const u8, u16) callconv(.c) QUIC_STATUS,
    ConnectionSetConfiguration: *const fn (HQUIC, HQUIC) callconv(.c) QUIC_STATUS,
    ConnectionSendResumptionTicket: *const fn (HQUIC, u32, u16, ?[*]const u8) callconv(.c) QUIC_STATUS,
    StreamOpen: *const fn (HQUIC, u32, QUIC_STREAM_CALLBACK_FN, ?*anyopaque, *HQUIC) callconv(.c) QUIC_STATUS,
    StreamClose: *const fn (HQUIC) callconv(.c) void,
    StreamStart: *const fn (HQUIC, u32) callconv(.c) QUIC_STATUS,
    StreamShutdown: *const fn (HQUIC, u32, u64) callconv(.c) void,
    StreamSend: *const fn (HQUIC, [*]const QUIC_BUFFER, u32, u32, ?*anyopaque) callconv(.c) QUIC_STATUS,
    StreamReceiveComplete: *const fn (HQUIC, u64) callconv(.c) void,
    StreamReceiveSetEnabled: *const fn (HQUIC, u8) callconv(.c) QUIC_STATUS,
    DatagramSend: *const fn (HQUIC, [*]const QUIC_BUFFER, u32, u32, ?*anyopaque) callconv(.c) QUIC_STATUS,
};

// API version
pub const QUIC_API_VERSION_2: u32 = 2;

// Entry points - link against msquic.dll
pub extern "msquic" fn MsQuicOpenVersion(Version: u32, QuicApi: *?*const QUIC_API_TABLE) callconv(.c) QUIC_STATUS;
pub extern "msquic" fn MsQuicClose(QuicApi: *const QUIC_API_TABLE) callconv(.c) void;

// High-level wrapper
pub const MsQuic = struct {
    api: *const QUIC_API_TABLE,

    const Self = @This();

    pub fn open() !Self {
        var api: ?*const QUIC_API_TABLE = null;
        const status = MsQuicOpenVersion(QUIC_API_VERSION_2, &api);
        if (QUIC_FAILED(status)) {
            std.log.err("MsQuicOpenVersion failed: 0x{X}", .{status});
            return error.MsQuicOpenFailed;
        }
        return Self{ .api = api.? };
    }

    pub fn close(self: *Self) void {
        MsQuicClose(self.api);
    }

    pub fn registrationOpen(self: *Self, config: *const QUIC_REGISTRATION_CONFIG) !HQUIC {
        var registration: HQUIC = null;
        const status = self.api.RegistrationOpen(config, &registration);
        if (QUIC_FAILED(status)) {
            std.log.err("RegistrationOpen failed: 0x{X}", .{status});
            return error.RegistrationOpenFailed;
        }
        return registration;
    }

    pub fn registrationClose(self: *Self, registration: HQUIC) void {
        self.api.RegistrationClose(registration);
    }

    pub fn configurationOpen(self: *Self, registration: HQUIC, alpn: []const QUIC_BUFFER, settings: ?*const QUIC_SETTINGS) !HQUIC {
        var configuration: HQUIC = null;
        const settings_size: u32 = if (settings != null) @sizeOf(QUIC_SETTINGS) else 0;
        const status = self.api.ConfigurationOpen(
            registration,
            alpn.ptr,
            @intCast(alpn.len),
            settings,
            settings_size,
            null,
            &configuration,
        );
        if (QUIC_FAILED(status)) {
            std.log.err("ConfigurationOpen failed: 0x{X}", .{status});
            return error.ConfigurationOpenFailed;
        }
        return configuration;
    }

    pub fn configurationClose(self: *Self, configuration: HQUIC) void {
        self.api.ConfigurationClose(configuration);
    }

    pub fn configurationLoadCredential(self: *Self, configuration: HQUIC, cred_config: *const QUIC_CREDENTIAL_CONFIG) !void {
        const status = self.api.ConfigurationLoadCredential(configuration, cred_config);
        if (QUIC_FAILED(status)) {
            std.log.err("ConfigurationLoadCredential failed: 0x{X}", .{status});
            return error.ConfigurationLoadCredentialFailed;
        }
    }

    pub fn listenerOpen(self: *Self, registration: HQUIC, handler: QUIC_LISTENER_CALLBACK_FN, context: ?*anyopaque) !HQUIC {
        var listener: HQUIC = null;
        const status = self.api.ListenerOpen(registration, handler, context, &listener);
        if (QUIC_FAILED(status)) {
            std.log.err("ListenerOpen failed: 0x{X}", .{status});
            return error.ListenerOpenFailed;
        }
        return listener;
    }

    pub fn listenerClose(self: *Self, listener: HQUIC) void {
        self.api.ListenerClose(listener);
    }

    pub fn listenerStart(self: *Self, listener: HQUIC, alpn: []const QUIC_BUFFER, local_addr: ?*const QUIC_ADDR) !void {
        const status = self.api.ListenerStart(listener, alpn.ptr, @intCast(alpn.len), local_addr);
        if (QUIC_FAILED(status)) {
            std.log.err("ListenerStart failed: 0x{X}", .{status});
            return error.ListenerStartFailed;
        }
    }

    pub fn listenerStop(self: *Self, listener: HQUIC) void {
        self.api.ListenerStop(listener);
    }

    pub fn connectionSetConfiguration(self: *Self, connection: HQUIC, configuration: HQUIC) !void {
        const status = self.api.ConnectionSetConfiguration(connection, configuration);
        if (QUIC_FAILED(status)) {
            std.log.err("ConnectionSetConfiguration failed: 0x{X}", .{status});
            return error.ConnectionSetConfigurationFailed;
        }
    }

    pub fn connectionClose(self: *Self, connection: HQUIC) void {
        self.api.ConnectionClose(connection);
    }

    pub fn connectionShutdown(self: *Self, connection: HQUIC, flags: u32, error_code: u64) void {
        self.api.ConnectionShutdown(connection, flags, error_code);
    }

    pub fn setCallbackHandler(self: *Self, handle: HQUIC, handler: anytype, context: ?*anyopaque) void {
        self.api.SetCallbackHandler(handle, @ptrCast(@constCast(&handler)), context);
    }

    pub fn setContext(self: *Self, handle: HQUIC, context: ?*anyopaque) void {
        self.api.SetContext(handle, context);
    }

    pub fn getContext(self: *Self, handle: HQUIC) ?*anyopaque {
        return self.api.GetContext(handle);
    }
};

// Flags
pub const QUIC_CONNECTION_SHUTDOWN_FLAG_NONE: u32 = 0x0000;
pub const QUIC_STREAM_OPEN_FLAG_NONE: u32 = 0x0000;
pub const QUIC_STREAM_START_FLAG_NONE: u32 = 0x0000;
pub const QUIC_SEND_FLAG_NONE: u32 = 0x0000;
pub const QUIC_SEND_FLAG_FIN: u32 = 0x0002;
