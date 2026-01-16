// Quiche C API bindings for Zig
// https://github.com/cloudflare/quiche

const std = @import("std");

// We'll use @cImport when we have the quiche headers available
// For now, define the types and functions manually

pub const QUICHE_PROTOCOL_VERSION: u32 = 0x00000001;
pub const MAX_CONN_ID_LEN: usize = 20;
pub const MAX_DATAGRAM_SIZE: usize = 1350;

// Opaque types
pub const Config = opaque {};
pub const Connection = opaque {};

// Error codes
pub const Error = enum(c_int) {
    done = -1,
    buffer_too_short = -2,
    unknown_version = -3,
    invalid_frame = -4,
    invalid_packet = -5,
    invalid_state = -6,
    invalid_stream_state = -7,
    invalid_transport_param = -8,
    crypto_fail = -9,
    tls_fail = -10,
    flow_control = -11,
    stream_limit = -12,
    stream_stopped = -15,
    stream_reset = -16,
    final_size = -13,
    congestion_control = -14,
    id_limit = -17,
    out_of_identifiers = -18,
    key_update = -19,
    _,

    pub fn isError(result: isize) bool {
        return result < 0;
    }
};

// Shutdown direction
pub const Shutdown = enum(c_int) {
    read = 0,
    write = 1,
};

// Receive info structure
pub const RecvInfo = extern struct {
    from: *std.posix.sockaddr,
    from_len: std.posix.socklen_t,
    to: *std.posix.sockaddr,
    to_len: std.posix.socklen_t,
};

// Send info structure
pub const SendInfo = extern struct {
    from: std.posix.sockaddr.storage,
    from_len: std.posix.socklen_t,
    to: std.posix.sockaddr.storage,
    to_len: std.posix.socklen_t,
    at: std.posix.timespec,
};

// Stream iterator
pub const StreamIter = opaque {};

// When we link against libquiche, these will be the actual C functions
// For now, they're declared but will fail to link without the library

pub extern fn quiche_config_new(version: u32) ?*Config;
pub extern fn quiche_config_free(config: *Config) void;

pub extern fn quiche_config_load_cert_chain_from_pem_file(config: *Config, path: [*:0]const u8) c_int;
pub extern fn quiche_config_load_priv_key_from_pem_file(config: *Config, path: [*:0]const u8) c_int;
pub extern fn quiche_config_set_application_protos(config: *Config, protos: [*]const u8, protos_len: usize) c_int;
pub extern fn quiche_config_set_max_idle_timeout(config: *Config, timeout: u64) void;
pub extern fn quiche_config_set_max_recv_udp_payload_size(config: *Config, size: usize) void;
pub extern fn quiche_config_set_max_send_udp_payload_size(config: *Config, size: usize) void;
pub extern fn quiche_config_set_initial_max_data(config: *Config, size: u64) void;
pub extern fn quiche_config_set_initial_max_stream_data_bidi_local(config: *Config, size: u64) void;
pub extern fn quiche_config_set_initial_max_stream_data_bidi_remote(config: *Config, size: u64) void;
pub extern fn quiche_config_set_initial_max_stream_data_uni(config: *Config, size: u64) void;
pub extern fn quiche_config_set_initial_max_streams_bidi(config: *Config, size: u64) void;
pub extern fn quiche_config_set_initial_max_streams_uni(config: *Config, size: u64) void;

pub extern fn quiche_accept(
    scid: [*]const u8,
    scid_len: usize,
    odcid: ?[*]const u8,
    odcid_len: usize,
    local: *const std.posix.sockaddr,
    local_len: std.posix.socklen_t,
    peer: *const std.posix.sockaddr,
    peer_len: std.posix.socklen_t,
    config: *Config,
) ?*Connection;

pub extern fn quiche_conn_free(conn: *Connection) void;

pub extern fn quiche_conn_recv(
    conn: *Connection,
    buf: [*]u8,
    buf_len: usize,
    info: *const RecvInfo,
) isize;

pub extern fn quiche_conn_send(
    conn: *Connection,
    out: [*]u8,
    out_len: usize,
    out_info: *SendInfo,
) isize;

pub extern fn quiche_conn_stream_recv(
    conn: *Connection,
    stream_id: u64,
    out: [*]u8,
    buf_len: usize,
    fin: *bool,
) isize;

pub extern fn quiche_conn_stream_send(
    conn: *Connection,
    stream_id: u64,
    buf: [*]const u8,
    buf_len: usize,
    fin: bool,
) isize;

pub extern fn quiche_conn_stream_shutdown(
    conn: *Connection,
    stream_id: u64,
    direction: Shutdown,
    err: u64,
) c_int;

pub extern fn quiche_conn_is_established(conn: *Connection) bool;
pub extern fn quiche_conn_is_closed(conn: *Connection) bool;
pub extern fn quiche_conn_is_draining(conn: *Connection) bool;

pub extern fn quiche_conn_readable(conn: *Connection) ?*StreamIter;
pub extern fn quiche_conn_writable(conn: *Connection) ?*StreamIter;

pub extern fn quiche_stream_iter_next(iter: *StreamIter, stream_id: *u64) bool;
pub extern fn quiche_stream_iter_free(iter: *StreamIter) void;

pub extern fn quiche_header_info(
    buf: [*]const u8,
    buf_len: usize,
    dcil: usize,
    version: *u32,
    ty: *u8,
    scid: [*]u8,
    scid_len: *usize,
    dcid: [*]u8,
    dcid_len: *usize,
    token: [*]u8,
    token_len: *usize,
) c_int;

pub extern fn quiche_version_is_supported(version: u32) bool;
