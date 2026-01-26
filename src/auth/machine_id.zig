/// Machine ID Detection
/// Platform-specific machine ID retrieval for encryption key derivation
const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.machine_id);

/// Machine ID source
pub const MachineIdSource = enum {
    /// Retrieved from platform-specific location
    system,
    /// Generated and stored locally (fallback)
    generated,
    /// Failed to obtain machine ID
    unavailable,
};

/// Machine ID result
pub const MachineIdResult = struct {
    uuid: [16]u8,
    source: MachineIdSource,
};

/// Get the machine's unique identifier
/// On Windows: Registry HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid
/// On Linux: /etc/machine-id or /var/lib/dbus/machine-id
/// On macOS: IOPlatformUUID via IOKit (not implemented, falls back to generated)
/// Fallback: Generate and store a random UUID in the config directory
pub fn getMachineId(allocator: std.mem.Allocator) MachineIdResult {
    // Try platform-specific first
    if (getPlatformMachineId()) |uuid| {
        log.debug("Retrieved machine ID from system", .{});
        return .{ .uuid = uuid, .source = .system };
    }

    // Fall back to generated ID stored in config
    if (getOrCreateFallbackId(allocator)) |uuid| {
        log.debug("Using generated machine ID from fallback file", .{});
        return .{ .uuid = uuid, .source = .generated };
    }

    log.warn("Failed to obtain machine ID", .{});
    return .{ .uuid = [_]u8{0} ** 16, .source = .unavailable };
}

/// Get machine ID from platform-specific source
fn getPlatformMachineId() ?[16]u8 {
    if (builtin.os.tag == .windows) {
        return getWindowsMachineGuid();
    } else if (builtin.os.tag == .linux) {
        return getLinuxMachineId();
    } else if (builtin.os.tag == .macos) {
        // macOS IOKit integration would go here
        // For now, fall back to generated
        return null;
    }
    return null;
}

/// Windows: Get machine ID
/// On Windows, we use the fallback file mechanism since registry access
/// requires additional Windows API bindings not in Zig's std.
fn getWindowsMachineGuid() ?[16]u8 {
    // Windows doesn't have easy access to MachineGuid via std.os.windows
    // Use the fallback file mechanism instead
    return null;
}

/// Linux: Read /etc/machine-id or /var/lib/dbus/machine-id
fn getLinuxMachineId() ?[16]u8 {
    if (builtin.os.tag != .linux) return null;

    const paths = [_][]const u8{
        "/etc/machine-id",
        "/var/lib/dbus/machine-id",
    };

    for (paths) |path| {
        if (readMachineIdFile(path)) |uuid| {
            return uuid;
        }
    }

    return null;
}

/// Read machine ID from a file (Linux format: 32 hex chars, no dashes)
fn readMachineIdFile(path: []const u8) ?[16]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();

    const file = std.Io.Dir.openFile(.cwd(), io, path, .{}) catch return null;
    defer file.close(io);

    var read_buf: [256]u8 = undefined;
    var reader = file.reader(io, &read_buf);

    // Read first line (32 hex chars + optional newline)
    var line_buf: [64]u8 = undefined;
    const line = reader.interface.readUntilDelimiter(&line_buf, '\n') catch |err| {
        if (err == error.EndOfStream) {
            // No newline, check if we got the full ID
            return null;
        }
        return null;
    };

    // Linux machine-id is 32 hex chars without dashes
    if (line.len >= 32) {
        return parseHexMachineId(line[0..32]) catch return null;
    }

    return null;
}

/// Parse 32 hex character machine ID (Linux format)
fn parseHexMachineId(hex: []const u8) ![16]u8 {
    if (hex.len != 32) return error.InvalidLength;

    var result: [16]u8 = undefined;
    for (0..16) |i| {
        const high = std.fmt.charToDigit(hex[i * 2], 16) catch return error.InvalidHex;
        const low = std.fmt.charToDigit(hex[i * 2 + 1], 16) catch return error.InvalidHex;
        result[i] = (high << 4) | low;
    }
    return result;
}

/// Parse UUID string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) to bytes
fn parseUuidString(uuid_str: []const u8) ![16]u8 {
    // Accept with or without dashes
    if (uuid_str.len == 36) {
        // With dashes
        var result: [16]u8 = undefined;
        var byte_idx: usize = 0;
        var i: usize = 0;

        while (i < uuid_str.len) : (i += 1) {
            if (uuid_str[i] == '-') continue;

            if (i + 1 >= uuid_str.len) return error.InvalidFormat;

            const high = std.fmt.charToDigit(uuid_str[i], 16) catch return error.InvalidHex;
            const low = std.fmt.charToDigit(uuid_str[i + 1], 16) catch return error.InvalidHex;
            result[byte_idx] = (high << 4) | low;
            byte_idx += 1;
            i += 1;
        }

        if (byte_idx != 16) return error.InvalidLength;
        return result;
    } else if (uuid_str.len == 32) {
        // Without dashes
        return parseHexMachineId(uuid_str);
    }

    return error.InvalidLength;
}

/// Get or create a fallback machine ID stored in a local file
fn getOrCreateFallbackId(allocator: std.mem.Allocator) ?[16]u8 {
    const fallback_file = ".machine_id";
    const io = std.Io.Threaded.global_single_threaded.io();

    // Try to read existing fallback ID
    if (std.Io.Dir.openFile(.cwd(), io, fallback_file, .{})) |file| {
        defer file.close(io);

        var read_buf: [64]u8 = undefined;
        var reader = file.reader(io, &read_buf);

        // Read the entire file content
        const content = reader.interface.allocRemaining(allocator, std.Io.Limit.limited(64)) catch {
            // Failed to read, will generate new ID
            return generateAndSaveFallbackId(io, fallback_file);
        };
        defer allocator.free(content);

        if (content.len >= 16) {
            var result: [16]u8 = undefined;
            @memcpy(&result, content[0..16]);
            return result;
        }
    } else |_| {}

    return generateAndSaveFallbackId(io, fallback_file);
}

/// Generate and save a new fallback machine ID
fn generateAndSaveFallbackId(io: anytype, fallback_file: []const u8) ?[16]u8 {
    // Generate new random ID
    var new_id: [16]u8 = undefined;
    io.random(&new_id);

    // Save to file
    if (std.Io.Dir.createFile(.cwd(), io, fallback_file, .{})) |file| {
        defer file.close(io);
        file.writeStreamingAll(io, &new_id) catch {
            log.warn("Failed to save fallback machine ID", .{});
        };
    } else |err| {
        log.warn("Failed to create fallback machine ID file: {}", .{err});
    }

    return new_id;
}

/// Format UUID bytes as string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
pub fn uuidToString(uuid: [16]u8) [36]u8 {
    const hex = "0123456789abcdef";
    var result: [36]u8 = undefined;
    var idx: usize = 0;

    for (0..16) |i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            result[idx] = '-';
            idx += 1;
        }
        result[idx] = hex[uuid[i] >> 4];
        idx += 1;
        result[idx] = hex[uuid[i] & 0x0F];
        idx += 1;
    }

    return result;
}

test "uuid string parsing with dashes" {
    const uuid_str = "550e8400-e29b-41d4-a716-446655440000";
    const uuid = try parseUuidString(uuid_str);
    try std.testing.expectEqual(@as(u8, 0x55), uuid[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), uuid[1]);
}

test "uuid string parsing without dashes" {
    const uuid_str = "550e8400e29b41d4a716446655440000";
    const uuid = try parseUuidString(uuid_str);
    try std.testing.expectEqual(@as(u8, 0x55), uuid[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), uuid[1]);
}

test "hex machine id parsing" {
    const hex = "550e8400e29b41d4a716446655440000";
    const uuid = try parseHexMachineId(hex);
    try std.testing.expectEqual(@as(u8, 0x55), uuid[0]);
}

test "uuid to string roundtrip" {
    const original: [16]u8 = .{ 0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4, 0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00 };
    const str = uuidToString(original);
    const parsed = try parseUuidString(&str);
    try std.testing.expectEqualSlices(u8, &original, &parsed);
}
