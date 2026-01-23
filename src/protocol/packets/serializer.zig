/// Hytale Protocol Packet Serialization
/// Matches the Java serialization format exactly
const std = @import("std");

/// Read a VarInt from buffer, returns (value, bytes_consumed)
pub fn readVarInt(data: []const u8) ?struct { value: u32, len: usize } {
    if (data.len == 0) return null;

    var value: u32 = 0;
    var shift: u5 = 0;
    var i: usize = 0;

    while (i < data.len and i < 5) {
        const b = data[i];
        value |= @as(u32, b & 0x7F) << shift;
        i += 1;
        if ((b & 0x80) == 0) {
            return .{ .value = value, .len = i };
        }
        shift +|= 7;
    }
    return null;
}

/// Write a VarInt to buffer, returns bytes written
pub fn writeVarInt(buf: []u8, value: u32) usize {
    var v = value;
    var i: usize = 0;
    while (v >= 0x80 and i < buf.len) {
        buf[i] = @as(u8, @truncate(v)) | 0x80;
        v >>= 7;
        i += 1;
    }
    if (i < buf.len) {
        buf[i] = @as(u8, @truncate(v));
        i += 1;
    }
    return i;
}

/// Calculate VarInt size for a value
pub fn varIntSize(value: u32) usize {
    if (value < 0x80) return 1;
    if (value < 0x4000) return 2;
    if (value < 0x200000) return 3;
    if (value < 0x10000000) return 4;
    return 5;
}

/// Read a fixed-length ASCII string
pub fn readFixedAsciiString(data: []const u8, len: usize) ?[]const u8 {
    if (data.len < len) return null;
    // Find the actual end (null-terminated or padded)
    var actual_len: usize = 0;
    for (data[0..len]) |c| {
        if (c == 0) break;
        actual_len += 1;
    }
    return data[0..actual_len];
}

/// Read a VarInt-prefixed string
pub fn readVarString(data: []const u8) ?struct { value: []const u8, len: usize } {
    const vi = readVarInt(data) orelse return null;
    const str_start = vi.len;
    const str_end = str_start + vi.value;
    if (data.len < str_end) return null;
    return .{ .value = data[str_start..str_end], .len = str_end };
}

/// Read a UUID (16 bytes, little-endian)
pub fn readUUID(data: []const u8) ?[16]u8 {
    if (data.len < 16) return null;
    var uuid: [16]u8 = undefined;
    @memcpy(&uuid, data[0..16]);
    return uuid;
}

/// Write a UUID
pub fn writeUUID(buf: []u8, uuid: [16]u8) void {
    @memcpy(buf[0..16], &uuid);
}

/// Parse Connect packet (ID=0)
/// Format from Java:
///   nullBits: 1 byte
///   protocolHash: 64 bytes fixed ASCII
///   clientType: 1 byte
///   uuid: 16 bytes
///   [offset table: 5 x 4 bytes = 20 bytes, starting at offset 82]
///   Variable block starts at offset 102
pub const ConnectPacket = struct {
    protocol_hash: []const u8,
    client_type: u8,
    uuid: [16]u8,
    language: ?[]const u8,
    identity_token: ?[]const u8,
    username: []const u8,

    pub fn parse(data: []const u8) ?ConnectPacket {
        // Minimum size is fixed block (82) + offset table (20) = 102
        if (data.len < 102) return null;

        const null_bits = data[0];
        const protocol_hash = readFixedAsciiString(data[1..], 64) orelse return null;
        const client_type = data[65];
        const uuid = readUUID(data[66..82]) orelse return null;

        // Read offset table (little-endian i32 values)
        const language_offset = std.mem.readInt(i32, data[82..86], .little);
        const identity_token_offset = std.mem.readInt(i32, data[86..90], .little);
        const username_offset = std.mem.readInt(i32, data[90..94], .little);
        // referral_data_offset at 94..98
        // referral_source_offset at 98..102

        const var_block_start: usize = 102;

        // Parse optional language (bit 0)
        var language: ?[]const u8 = null;
        if ((null_bits & 1) != 0 and language_offset >= 0) {
            const pos = var_block_start + @as(usize, @intCast(language_offset));
            if (pos < data.len) {
                const vs = readVarString(data[pos..]) orelse return null;
                language = vs.value;
            }
        }

        // Parse optional identity token (bit 1)
        var identity_token: ?[]const u8 = null;
        if ((null_bits & 2) != 0 and identity_token_offset >= 0) {
            const pos = var_block_start + @as(usize, @intCast(identity_token_offset));
            if (pos < data.len) {
                const vs = readVarString(data[pos..]) orelse return null;
                identity_token = vs.value;
            }
        }

        // Parse username (required)
        if (username_offset < 0) return null;
        const username_pos = var_block_start + @as(usize, @intCast(username_offset));
        if (username_pos >= data.len) return null;
        const username_result = readVarString(data[username_pos..]) orelse return null;

        return ConnectPacket{
            .protocol_hash = protocol_hash,
            .client_type = client_type,
            .uuid = uuid,
            .language = language,
            .identity_token = identity_token,
            .username = username_result.value,
        };
    }
};

/// Serialize ConnectAccept packet (ID=14)
/// Format: [1 byte nullBits] + optional [VarInt len + bytes] passwordChallenge
pub fn serializeConnectAccept(allocator: std.mem.Allocator, password_challenge: ?[]const u8) ![]u8 {
    if (password_challenge) |challenge| {
        // Has password challenge
        const vi_size = varIntSize(@intCast(challenge.len));
        const total_size = 1 + vi_size + challenge.len;
        const buf = try allocator.alloc(u8, total_size);
        buf[0] = 0x01; // nullBits: bit 0 set
        _ = writeVarInt(buf[1..], @intCast(challenge.len));
        @memcpy(buf[1 + vi_size ..], challenge);
        return buf;
    } else {
        // No password challenge
        const buf = try allocator.alloc(u8, 1);
        buf[0] = 0x00; // nullBits: no optional fields
        return buf;
    }
}

/// Serialize WorldSettings packet (ID=20)
/// Format: [1 byte nullBits] [4 bytes worldHeight LE] + optional assets array
pub fn serializeWorldSettings(allocator: std.mem.Allocator, world_height: i32) ![]u8 {
    // For now, send without required assets (null)
    const buf = try allocator.alloc(u8, 5);
    buf[0] = 0x00; // nullBits: no optional fields (requiredAssets = null)
    std.mem.writeInt(i32, buf[1..5], world_height, .little);
    return buf;
}

/// Serialize ServerInfo packet (ID=223)
/// Format:
///   nullBits: 1 byte
///   maxPlayers: 4 bytes LE
///   serverNameOffset: 4 bytes LE (offset from var block start)
///   motdOffset: 4 bytes LE
///   Variable block: serverName?, motd?
pub fn serializeServerInfo(allocator: std.mem.Allocator, server_name: ?[]const u8, motd: ?[]const u8, max_players: i32) ![]u8 {
    var null_bits: u8 = 0;
    var var_data: std.ArrayListUnmanaged(u8) = .empty;
    defer var_data.deinit(allocator);

    var server_name_offset: i32 = -1;
    var motd_offset: i32 = -1;

    // Write serverName if present
    if (server_name) |name| {
        null_bits |= 0x01;
        server_name_offset = @intCast(var_data.items.len);
        // Write VarInt length
        var vi_buf: [5]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, @intCast(name.len));
        try var_data.appendSlice(allocator, vi_buf[0..vi_len]);
        try var_data.appendSlice(allocator, name);
    }

    // Write motd if present
    if (motd) |m| {
        null_bits |= 0x02;
        motd_offset = @intCast(var_data.items.len);
        var vi_buf: [5]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, @intCast(m.len));
        try var_data.appendSlice(allocator, vi_buf[0..vi_len]);
        try var_data.appendSlice(allocator, m);
    }

    // Fixed block: nullBits(1) + maxPlayers(4) + serverNameOffset(4) + motdOffset(4) = 13
    const fixed_size: usize = 13;
    const total_size = fixed_size + var_data.items.len;
    const buf = try allocator.alloc(u8, total_size);

    buf[0] = null_bits;
    std.mem.writeInt(i32, buf[1..5], max_players, .little);
    std.mem.writeInt(i32, buf[5..9], server_name_offset, .little);
    std.mem.writeInt(i32, buf[9..13], motd_offset, .little);

    // Write variable data
    @memcpy(buf[fixed_size..], var_data.items);

    return buf;
}

/// Serialize WorldLoadProgress packet (ID=21)
/// Format: nullBits(1) + current(4) + total(4) + [offset(4)] + [message VarString]
pub fn serializeWorldLoadProgress(allocator: std.mem.Allocator, message: ?[]const u8, current: i32, total: i32) ![]u8 {
    var null_bits: u8 = 0;
    var var_data: std.ArrayListUnmanaged(u8) = .empty;
    defer var_data.deinit(allocator);

    var message_offset: i32 = -1;

    if (message) |msg| {
        null_bits |= 0x01;
        message_offset = 0;
        var vi_buf: [5]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, @intCast(msg.len));
        try var_data.appendSlice(allocator, vi_buf[0..vi_len]);
        try var_data.appendSlice(allocator, msg);
    }

    // Fixed block: nullBits(1) + current(4) + total(4) + messageOffset(4) = 13
    const fixed_size: usize = 13;
    const total_size = fixed_size + var_data.items.len;
    const buf = try allocator.alloc(u8, total_size);

    buf[0] = null_bits;
    std.mem.writeInt(i32, buf[1..5], current, .little);
    std.mem.writeInt(i32, buf[5..9], total, .little);
    std.mem.writeInt(i32, buf[9..13], message_offset, .little);

    @memcpy(buf[fixed_size..], var_data.items);

    return buf;
}

/// Serialize WorldLoadFinished packet (ID=22)
/// Format: empty packet (0 bytes)
pub fn serializeWorldLoadFinished(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.alloc(u8, 0);
}

/// Serialize PasswordAccepted packet (ID=16)
/// Format: empty packet (0 bytes)
pub fn serializePasswordAccepted(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.alloc(u8, 0);
}

/// DisconnectType enum matching Java
pub const DisconnectType = enum(u8) {
    Disconnect = 0,
    Kick = 1,
    Ban = 2,
    Leave = 3,
    Crash = 4,
    Timeout = 5,
    ServerShutdown = 6,
};

/// Serialize Disconnect packet (ID=1)
/// Format: [1 byte nullBits] [1 byte type] [optional VarString reason]
pub fn serializeDisconnect(allocator: std.mem.Allocator, reason: ?[]const u8, disconnect_type: DisconnectType) ![]u8 {
    if (reason) |r| {
        const vi_size = varIntSize(@intCast(r.len));
        const total_size = 2 + vi_size + r.len;
        const buf = try allocator.alloc(u8, total_size);
        buf[0] = 0x01; // nullBits: bit 0 set (reason present)
        buf[1] = @intFromEnum(disconnect_type);
        _ = writeVarInt(buf[2..], @intCast(r.len));
        @memcpy(buf[2 + vi_size ..], r);
        return buf;
    } else {
        const buf = try allocator.alloc(u8, 2);
        buf[0] = 0x00; // nullBits: no optional fields
        buf[1] = @intFromEnum(disconnect_type);
        return buf;
    }
}

/// UUID to string format
pub fn uuidToString(uuid: [16]u8) [36]u8 {
    const hex_chars = "0123456789abcdef";
    var result: [36]u8 = undefined;
    var out_idx: usize = 0;

    for (0..16) |i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            result[out_idx] = '-';
            out_idx += 1;
        }
        result[out_idx] = hex_chars[uuid[i] >> 4];
        out_idx += 1;
        result[out_idx] = hex_chars[uuid[i] & 0x0F];
        out_idx += 1;
    }

    return result;
}

test "parse Connect packet" {
    // Build a minimal Connect packet
    var data: [120]u8 = undefined;
    @memset(&data, 0);

    // nullBits
    data[0] = 0x00; // no optional fields

    // protocolHash (64 bytes fixed ASCII) - starts at offset 1
    const hash = "6708f121966c1c443f4b0eb525b2f81d0a8dc61f5003a692a8fa157e5e02cea9";
    @memcpy(data[1..65], hash);

    // clientType at offset 65
    data[65] = 0x00; // Game

    // uuid at offset 66-81
    @memset(data[66..82], 0xAB);

    // Offset table at 82-101
    std.mem.writeInt(i32, data[82..86], -1, .little); // language offset
    std.mem.writeInt(i32, data[86..90], -1, .little); // identity token offset
    std.mem.writeInt(i32, data[90..94], 0, .little); // username offset (relative to var block)
    std.mem.writeInt(i32, data[94..98], -1, .little); // referral data offset
    std.mem.writeInt(i32, data[98..102], -1, .little); // referral source offset

    // Variable block at 102+
    data[102] = 4; // VarInt: username length = 4
    @memcpy(data[103..107], "Test");

    const result = ConnectPacket.parse(&data);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings(hash, result.?.protocol_hash);
    try std.testing.expectEqualStrings("Test", result.?.username);
}

test "serialize ConnectAccept" {
    const allocator = std.testing.allocator;

    // Without password
    const no_pw = try serializeConnectAccept(allocator, null);
    defer allocator.free(no_pw);
    try std.testing.expectEqual(@as(usize, 1), no_pw.len);
    try std.testing.expectEqual(@as(u8, 0), no_pw[0]);

    // With password challenge
    const challenge = [_]u8{ 1, 2, 3, 4 };
    const with_pw = try serializeConnectAccept(allocator, &challenge);
    defer allocator.free(with_pw);
    try std.testing.expectEqual(@as(usize, 6), with_pw.len); // 1 + 1 + 4
    try std.testing.expectEqual(@as(u8, 1), with_pw[0]); // nullBits
}
