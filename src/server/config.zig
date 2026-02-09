const std = @import("std");

const log = std.log.scoped(.config);

/// Debug configuration flags for crash isolation.
/// Set environment variables to enable:
///   ZYTALE_NO_COMPRESS=1  — bypass zstd compression on outgoing packets
///   ZYTALE_MINIMAL_BLOCKS=1 — send only the air block (ID 0) in UpdateBlockTypes
///   ZYTALE_HEX_DUMP=1 — hex-dump first 128 bytes of each outgoing packet payload
pub const DebugConfig = struct {
    bypass_compression: bool = false,
    minimal_blocks: bool = false,
    hex_dump_packets: bool = false,

    /// Read debug flags from environment variables.
    pub fn initFromEnv() DebugConfig {
        var cfg = DebugConfig{};

        const environ: std.process.Environ = .{ .block = .global };
        var env_map = environ.createMap(std.heap.page_allocator) catch return cfg;
        defer env_map.deinit();

        if (env_map.get("ZYTALE_NO_COMPRESS")) |val| {
            cfg.bypass_compression = std.mem.eql(u8, val, "1");
        }

        if (env_map.get("ZYTALE_MINIMAL_BLOCKS")) |val| {
            cfg.minimal_blocks = std.mem.eql(u8, val, "1");
        }

        if (env_map.get("ZYTALE_HEX_DUMP")) |val| {
            cfg.hex_dump_packets = std.mem.eql(u8, val, "1");
        }

        if (cfg.bypass_compression) log.warn("DEBUG: compression bypass ENABLED (ZYTALE_NO_COMPRESS=1)", .{});
        if (cfg.minimal_blocks) log.warn("DEBUG: minimal blocks mode ENABLED (ZYTALE_MINIMAL_BLOCKS=1)", .{});
        if (cfg.hex_dump_packets) log.warn("DEBUG: hex dump ENABLED (ZYTALE_HEX_DUMP=1)", .{});

        return cfg;
    }

    /// Global singleton — initialized once at startup.
    var global: ?DebugConfig = null;

    pub fn get() DebugConfig {
        if (global) |cfg| return cfg;
        global = initFromEnv();
        return global.?;
    }
};
