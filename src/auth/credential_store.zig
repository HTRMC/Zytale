/// Credential Store
/// Persists authentication tokens to disk for automatic login
const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.credential_store);

/// Default credential file name
pub const DEFAULT_CREDENTIAL_FILE = "server_auth.json";

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io) catch return 0;
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Stored credentials structure
pub const StoredCredentials = struct {
    /// Session token for Session Service API calls
    session_token: ?[]const u8 = null,

    /// Identity token sent to clients
    identity_token: ?[]const u8 = null,

    /// OAuth access token
    access_token: ?[]const u8 = null,

    /// OAuth refresh token for token renewal
    refresh_token: ?[]const u8 = null,

    /// Profile UUID (hex string)
    profile_uuid: ?[]const u8 = null,

    /// Profile username
    username: ?[]const u8 = null,

    /// Token expiration timestamp (Unix epoch seconds)
    expires_at: i64 = 0,

    /// Check if credentials are present and not expired
    pub fn isValid(self: *const StoredCredentials) bool {
        if (self.session_token == null or self.identity_token == null) {
            return false;
        }
        // Check expiration with 5 minute buffer
        const now = getTimestamp();
        return now < (self.expires_at - 300);
    }

    /// Check if refresh token is available for renewal
    pub fn canRefresh(self: *const StoredCredentials) bool {
        return self.refresh_token != null and self.access_token != null;
    }
};

/// Credential store for loading/saving authentication tokens
pub const CredentialStore = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    file_path_owned: bool,

    const Self = @This();

    /// Initialize with default file path in current directory
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .file_path = DEFAULT_CREDENTIAL_FILE,
            .file_path_owned = false,
        };
    }

    /// Initialize with custom file path
    pub fn initWithPath(allocator: std.mem.Allocator, path: []const u8) !Self {
        const owned_path = try allocator.dupe(u8, path);
        return .{
            .allocator = allocator,
            .file_path = owned_path,
            .file_path_owned = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.file_path_owned) {
            self.allocator.free(self.file_path);
        }
    }

    /// Load credentials from disk
    /// Returns null if file doesn't exist or is invalid
    pub fn load(self: *Self) ?StoredCredentials {
        log.info("Loading credentials from {s}", .{self.file_path});

        // Get I/O handle
        const io = std.Io.Threaded.global_single_threaded.io();

        // Read file contents using openFile from cwd
        const file = std.Io.Dir.openFile(.cwd(), io, self.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                log.debug("Credential file not found", .{});
            } else {
                log.warn("Failed to open credential file: {}", .{err});
            }
            return null;
        };
        defer file.close(io);

        // Read file content using reader
        var read_buf: [65536]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);
        const content = file_reader.interface.allocRemaining(self.allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| {
            log.warn("Failed to read credential file: {}", .{err});
            return null;
        };
        defer self.allocator.free(content);

        // Parse JSON
        const parsed = std.json.parseFromSlice(struct {
            session_token: ?[]const u8 = null,
            identity_token: ?[]const u8 = null,
            access_token: ?[]const u8 = null,
            refresh_token: ?[]const u8 = null,
            profile_uuid: ?[]const u8 = null,
            username: ?[]const u8 = null,
            expires_at: i64 = 0,
        }, self.allocator, content, .{}) catch |err| {
            log.warn("Failed to parse credential file: {}", .{err});
            return null;
        };
        defer parsed.deinit();

        // Duplicate strings since parsed will be freed
        var creds = StoredCredentials{
            .expires_at = parsed.value.expires_at,
        };

        if (parsed.value.session_token) |token| {
            creds.session_token = self.allocator.dupe(u8, token) catch return null;
        }
        if (parsed.value.identity_token) |token| {
            creds.identity_token = self.allocator.dupe(u8, token) catch return null;
        }
        if (parsed.value.access_token) |token| {
            creds.access_token = self.allocator.dupe(u8, token) catch return null;
        }
        if (parsed.value.refresh_token) |token| {
            creds.refresh_token = self.allocator.dupe(u8, token) catch return null;
        }
        if (parsed.value.profile_uuid) |uuid| {
            creds.profile_uuid = self.allocator.dupe(u8, uuid) catch return null;
        }
        if (parsed.value.username) |name| {
            creds.username = self.allocator.dupe(u8, name) catch return null;
        }

        if (creds.isValid()) {
            log.info("Loaded valid credentials for: {s}", .{creds.username orelse "unknown"});
        } else if (creds.canRefresh()) {
            log.info("Loaded expired credentials (can refresh)", .{});
        } else {
            log.info("Loaded invalid/expired credentials", .{});
        }

        return creds;
    }

    /// Save credentials to disk
    pub fn save(self: *Self, creds: *const StoredCredentials) !void {
        log.info("Saving credentials to {s}", .{self.file_path});

        // Build JSON content
        var json_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer json_buf.deinit(self.allocator);

        try json_buf.appendSlice(self.allocator, "{\n");

        var first = true;

        if (creds.session_token) |token| {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            try json_buf.appendSlice(self.allocator, "  \"session_token\": \"");
            try appendJsonEscaped(self.allocator, &json_buf, token);
            try json_buf.appendSlice(self.allocator, "\"");
            first = false;
        }

        if (creds.identity_token) |token| {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            try json_buf.appendSlice(self.allocator, "  \"identity_token\": \"");
            try appendJsonEscaped(self.allocator, &json_buf, token);
            try json_buf.appendSlice(self.allocator, "\"");
            first = false;
        }

        if (creds.access_token) |token| {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            try json_buf.appendSlice(self.allocator, "  \"access_token\": \"");
            try appendJsonEscaped(self.allocator, &json_buf, token);
            try json_buf.appendSlice(self.allocator, "\"");
            first = false;
        }

        if (creds.refresh_token) |token| {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            try json_buf.appendSlice(self.allocator, "  \"refresh_token\": \"");
            try appendJsonEscaped(self.allocator, &json_buf, token);
            try json_buf.appendSlice(self.allocator, "\"");
            first = false;
        }

        if (creds.profile_uuid) |uuid| {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            try json_buf.appendSlice(self.allocator, "  \"profile_uuid\": \"");
            try appendJsonEscaped(self.allocator, &json_buf, uuid);
            try json_buf.appendSlice(self.allocator, "\"");
            first = false;
        }

        if (creds.username) |name| {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            try json_buf.appendSlice(self.allocator, "  \"username\": \"");
            try appendJsonEscaped(self.allocator, &json_buf, name);
            try json_buf.appendSlice(self.allocator, "\"");
            first = false;
        }

        if (creds.expires_at != 0) {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            const expires_str = try std.fmt.allocPrint(self.allocator, "  \"expires_at\": {d}", .{creds.expires_at});
            defer self.allocator.free(expires_str);
            try json_buf.appendSlice(self.allocator, expires_str);
        }

        try json_buf.appendSlice(self.allocator, "\n}\n");

        // Get I/O handle
        const io = std.Io.Threaded.global_single_threaded.io();

        // Write to file
        const file = std.Io.Dir.createFile(.cwd(), io, self.file_path, .{}) catch |err| {
            log.err("Failed to create credential file: {}", .{err});
            return err;
        };
        defer file.close(io);

        file.writeStreamingAll(io, json_buf.items) catch |err| {
            log.err("Failed to write credential file: {}", .{err});
            return err;
        };
        log.info("Credentials saved successfully", .{});
    }

    /// Delete stored credentials
    pub fn clear(self: *Self) void {
        log.info("Clearing stored credentials", .{});
        const io = std.Io.Threaded.global_single_threaded.io();
        std.Io.Dir.deleteFile(.cwd(), io, self.file_path) catch |err| {
            if (err != error.FileNotFound) {
                log.warn("Failed to delete credential file: {}", .{err});
            }
        };
    }

    /// Free credentials loaded by load()
    pub fn freeCredentials(self: *Self, creds: *StoredCredentials) void {
        if (creds.session_token) |token| self.allocator.free(token);
        if (creds.identity_token) |token| self.allocator.free(token);
        if (creds.access_token) |token| self.allocator.free(token);
        if (creds.refresh_token) |token| self.allocator.free(token);
        if (creds.profile_uuid) |uuid| self.allocator.free(uuid);
        if (creds.username) |name| self.allocator.free(name);
        creds.* = .{};
    }
};

/// Append JSON-escaped string to list
fn appendJsonEscaped(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(u8), s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    // Control characters - encode as \u00XX
                    var buf: [6]u8 = undefined;
                    _ = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
                    try list.appendSlice(allocator, &buf);
                } else {
                    try list.append(allocator, c);
                }
            },
        }
    }
}

test "credential store init" {
    const allocator = std.testing.allocator;

    var store = CredentialStore.init(allocator);
    defer store.deinit();

    try std.testing.expectEqualStrings(DEFAULT_CREDENTIAL_FILE, store.file_path);
}

test "stored credentials validation" {
    // Invalid: missing tokens
    const empty_creds = StoredCredentials{};
    try std.testing.expect(!empty_creds.isValid());
    try std.testing.expect(!empty_creds.canRefresh());

    // Valid credentials (far future expiration)
    const valid_creds = StoredCredentials{
        .session_token = "session",
        .identity_token = "identity",
        .expires_at = getTimestamp() + 3600,
    };
    try std.testing.expect(valid_creds.isValid());

    // Expired credentials
    const expired_creds = StoredCredentials{
        .session_token = "session",
        .identity_token = "identity",
        .expires_at = getTimestamp() - 3600,
    };
    try std.testing.expect(!expired_creds.isValid());

    // Can refresh
    const refresh_creds = StoredCredentials{
        .access_token = "access",
        .refresh_token = "refresh",
    };
    try std.testing.expect(refresh_creds.canRefresh());
}
