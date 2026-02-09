/// Encrypted Credential Store
/// Persists authentication credentials encrypted with AES-256-GCM
/// Key is derived from machine ID using PBKDF2 (matching Java implementation)
const std = @import("std");
const machine_id = @import("machine_id.zig");

const log = std.log.scoped(.encrypted_credential_store);

/// Default encrypted credential file name
pub const DEFAULT_ENCRYPTED_FILE = "auth.enc";

/// PBKDF2 iterations (matching Java: 100,000)
const PBKDF2_ITERATIONS: u32 = 100_000;

/// GCM nonce length
const GCM_NONCE_LENGTH = 12;

/// AES-256 key length
const AES_KEY_LENGTH = 32;

/// Salt for PBKDF2 (matching Java: "HytaleAuthCredentialStore")
const PBKDF2_SALT = "HytaleAuthCredentialStore";

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io);
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Stored credentials structure (for encrypted storage)
pub const StoredCredentials = struct {
    /// OAuth access token
    access_token: ?[]const u8 = null,

    /// OAuth refresh token for token renewal
    refresh_token: ?[]const u8 = null,

    /// Token expiration timestamp (Unix epoch seconds)
    expires_at: i64 = 0,

    /// Selected profile UUID (16 bytes)
    profile_uuid: ?[16]u8 = null,

    /// Profile username
    username: ?[]const u8 = null,

    /// Account UUID (the account may have multiple profiles)
    account_uuid: ?[16]u8 = null,

    /// Check if credentials have a valid refresh token
    pub fn canRefresh(self: *const StoredCredentials) bool {
        return self.refresh_token != null;
    }

    /// Check if access token is still valid (with 5 minute buffer)
    pub fn isAccessTokenValid(self: *const StoredCredentials) bool {
        if (self.access_token == null) return false;
        const now = getTimestamp();
        return now < (self.expires_at - 300);
    }
};

/// Encrypted credential store for secure token persistence
pub const EncryptedCredentialStore = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    file_path_owned: bool,
    encryption_key: ?[AES_KEY_LENGTH]u8,
    machine_id_source: machine_id.MachineIdSource,

    const Self = @This();

    /// Initialize with default file path
    pub fn init(allocator: std.mem.Allocator) Self {
        var store = Self{
            .allocator = allocator,
            .file_path = DEFAULT_ENCRYPTED_FILE,
            .file_path_owned = false,
            .encryption_key = null,
            .machine_id_source = .unavailable,
        };

        store.deriveKey();
        return store;
    }

    /// Initialize with custom file path
    pub fn initWithPath(allocator: std.mem.Allocator, path: []const u8) !Self {
        const owned_path = try allocator.dupe(u8, path);
        var store = Self{
            .allocator = allocator,
            .file_path = owned_path,
            .file_path_owned = true,
            .encryption_key = null,
            .machine_id_source = .unavailable,
        };

        store.deriveKey();
        return store;
    }

    pub fn deinit(self: *Self) void {
        if (self.file_path_owned) {
            self.allocator.free(self.file_path);
        }
        // Zero out the key for security
        if (self.encryption_key != null) {
            @memset(&self.encryption_key.?, 0);
        }
    }

    /// Derive encryption key from machine ID using PBKDF2
    fn deriveKey(self: *Self) void {
        const mid = machine_id.getMachineId(self.allocator);
        self.machine_id_source = mid.source;

        if (mid.source == .unavailable) {
            log.warn("Cannot derive encryption key - machine ID unavailable", .{});
            self.encryption_key = null;
            return;
        }

        // Convert machine ID UUID to string for PBKDF2 password
        const uuid_str = machine_id.uuidToString(mid.uuid);

        // Derive key using PBKDF2-SHA256
        var derived_key: [AES_KEY_LENGTH]u8 = undefined;
        std.crypto.pwhash.pbkdf2(
            &derived_key,
            &uuid_str,
            PBKDF2_SALT,
            PBKDF2_ITERATIONS,
            std.crypto.auth.hmac.sha2.HmacSha256,
        ) catch {
            log.warn("Failed to derive encryption key", .{});
            self.encryption_key = null;
            return;
        };

        self.encryption_key = derived_key;
        log.debug("Encryption key derived from machine ID (source: {})", .{mid.source});
    }

    /// Check if encryption is available
    pub fn isEncryptionAvailable(self: *const Self) bool {
        return self.encryption_key != null;
    }

    /// Load credentials from encrypted file
    pub fn load(self: *Self) ?StoredCredentials {
        if (self.encryption_key == null) {
            log.warn("Cannot load credentials - encryption key unavailable", .{});
            return null;
        }

        log.info("Loading encrypted credentials from {s}", .{self.file_path});

        const io = std.Io.Threaded.global_single_threaded.io();

        // Read encrypted file
        const file = std.Io.Dir.openFile(.cwd(), io, self.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                log.debug("Encrypted credential file not found", .{});
            } else {
                log.warn("Failed to open encrypted credential file: {}", .{err});
            }
            return null;
        };
        defer file.close(io);

        var read_buf: [65536]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);
        const encrypted = file_reader.interface.allocRemaining(self.allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| {
            log.warn("Failed to read encrypted credential file: {}", .{err});
            return null;
        };
        defer self.allocator.free(encrypted);

        // Decrypt
        const plaintext = self.decrypt(encrypted) orelse {
            log.warn("Failed to decrypt credentials - file may be corrupted or from different hardware", .{});
            return null;
        };
        defer self.allocator.free(plaintext);

        // Parse JSON
        return self.parseCredentials(plaintext);
    }

    /// Save credentials to encrypted file
    pub fn save(self: *Self, creds: *const StoredCredentials) !void {
        if (self.encryption_key == null) {
            log.warn("Cannot save credentials - encryption key unavailable", .{});
            return error.NoEncryptionKey;
        }

        log.info("Saving encrypted credentials to {s}", .{self.file_path});

        // Serialize to JSON
        const json = try self.serializeCredentials(creds);
        defer self.allocator.free(json);

        // Encrypt
        const encrypted = try self.encrypt(json);
        defer self.allocator.free(encrypted);

        // Write to file
        const io = std.Io.Threaded.global_single_threaded.io();
        const file = std.Io.Dir.createFile(.cwd(), io, self.file_path, .{}) catch |err| {
            log.err("Failed to create encrypted credential file: {}", .{err});
            return err;
        };
        defer file.close(io);

        file.writeStreamingAll(io, encrypted) catch |err| {
            log.err("Failed to write encrypted credential file: {}", .{err});
            return err;
        };

        log.info("Encrypted credentials saved successfully", .{});
    }

    /// Clear stored credentials (delete file)
    pub fn clear(self: *Self) void {
        log.info("Clearing encrypted credentials", .{});
        const io = std.Io.Threaded.global_single_threaded.io();
        std.Io.Dir.deleteFile(.cwd(), io, self.file_path) catch |err| {
            if (err != error.FileNotFound) {
                log.warn("Failed to delete encrypted credential file: {}", .{err});
            }
        };
    }

    /// Encrypt data using AES-256-GCM
    /// Format: [12-byte nonce][ciphertext + 16-byte auth tag]
    fn encrypt(self: *Self, plaintext: []const u8) ![]u8 {
        const key = self.encryption_key orelse return error.NoEncryptionKey;
        const io = std.Io.Threaded.global_single_threaded.io();

        // Generate random nonce
        var nonce: [GCM_NONCE_LENGTH]u8 = undefined;
        io.random(&nonce);

        // Allocate output buffer: nonce + ciphertext + tag
        const output_len = GCM_NONCE_LENGTH + plaintext.len + 16; // 16 = auth tag
        const output = try self.allocator.alloc(u8, output_len);
        errdefer self.allocator.free(output);

        // Copy nonce to output
        @memcpy(output[0..GCM_NONCE_LENGTH], &nonce);

        // Encrypt
        var tag: [16]u8 = undefined;
        std.crypto.aead.aes_gcm.Aes256Gcm.encrypt(
            output[GCM_NONCE_LENGTH .. output_len - 16],
            &tag,
            plaintext,
            "",
            nonce,
            key,
        );

        // Append auth tag
        @memcpy(output[output_len - 16 ..], &tag);

        return output;
    }

    /// Decrypt data using AES-256-GCM
    fn decrypt(self: *Self, encrypted: []const u8) ?[]u8 {
        const key = self.encryption_key orelse return null;

        // Minimum size: nonce + tag
        if (encrypted.len < GCM_NONCE_LENGTH + 16) {
            return null;
        }

        // Extract nonce
        const nonce: [GCM_NONCE_LENGTH]u8 = encrypted[0..GCM_NONCE_LENGTH].*;

        // Extract ciphertext and tag
        const ciphertext = encrypted[GCM_NONCE_LENGTH .. encrypted.len - 16];
        var tag: [16]u8 = undefined;
        @memcpy(&tag, encrypted[encrypted.len - 16 ..][0..16]);

        // Allocate output buffer
        const plaintext = self.allocator.alloc(u8, ciphertext.len) catch return null;
        errdefer self.allocator.free(plaintext);

        // Decrypt
        std.crypto.aead.aes_gcm.Aes256Gcm.decrypt(
            plaintext,
            ciphertext,
            tag,
            "",
            nonce,
            key,
        ) catch {
            self.allocator.free(plaintext);
            return null;
        };

        return plaintext;
    }

    /// Serialize credentials to JSON
    fn serializeCredentials(self: *Self, creds: *const StoredCredentials) ![]u8 {
        var json_buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer json_buf.deinit(self.allocator);

        try json_buf.appendSlice(self.allocator, "{\n");

        var first = true;

        if (creds.access_token) |token| {
            try self.appendJsonField(&json_buf, "access_token", token, &first);
        }

        if (creds.refresh_token) |token| {
            try self.appendJsonField(&json_buf, "refresh_token", token, &first);
        }

        if (creds.expires_at != 0) {
            if (!first) try json_buf.appendSlice(self.allocator, ",\n");
            const expires_str = try std.fmt.allocPrint(self.allocator, "  \"expires_at\": {d}", .{creds.expires_at});
            defer self.allocator.free(expires_str);
            try json_buf.appendSlice(self.allocator, expires_str);
            first = false;
        }

        if (creds.profile_uuid) |uuid| {
            const uuid_str = machine_id.uuidToString(uuid);
            try self.appendJsonField(&json_buf, "profile_uuid", &uuid_str, &first);
        }

        if (creds.username) |name| {
            try self.appendJsonField(&json_buf, "username", name, &first);
        }

        if (creds.account_uuid) |uuid| {
            const uuid_str = machine_id.uuidToString(uuid);
            try self.appendJsonField(&json_buf, "account_uuid", &uuid_str, &first);
        }

        try json_buf.appendSlice(self.allocator, "\n}\n");

        return json_buf.toOwnedSlice(self.allocator);
    }

    /// Append a JSON string field
    fn appendJsonField(self: *Self, buf: *std.ArrayListUnmanaged(u8), key: []const u8, value: []const u8, first: *bool) !void {
        if (!first.*) try buf.appendSlice(self.allocator, ",\n");
        try buf.appendSlice(self.allocator, "  \"");
        try buf.appendSlice(self.allocator, key);
        try buf.appendSlice(self.allocator, "\": \"");
        try appendJsonEscaped(self.allocator, buf, value);
        try buf.appendSlice(self.allocator, "\"");
        first.* = false;
    }

    /// Parse credentials from JSON
    fn parseCredentials(self: *Self, json: []const u8) ?StoredCredentials {
        const parsed = std.json.parseFromSlice(struct {
            access_token: ?[]const u8 = null,
            refresh_token: ?[]const u8 = null,
            expires_at: i64 = 0,
            profile_uuid: ?[]const u8 = null,
            username: ?[]const u8 = null,
            account_uuid: ?[]const u8 = null,
        }, self.allocator, json, .{}) catch |err| {
            log.warn("Failed to parse credential JSON: {}", .{err});
            return null;
        };
        defer parsed.deinit();

        var creds = StoredCredentials{
            .expires_at = parsed.value.expires_at,
        };

        // Duplicate strings
        if (parsed.value.access_token) |token| {
            creds.access_token = self.allocator.dupe(u8, token) catch return null;
        }
        if (parsed.value.refresh_token) |token| {
            creds.refresh_token = self.allocator.dupe(u8, token) catch return null;
        }
        if (parsed.value.username) |name| {
            creds.username = self.allocator.dupe(u8, name) catch return null;
        }

        // Parse UUIDs
        if (parsed.value.profile_uuid) |uuid_str| {
            creds.profile_uuid = parseUuidString(uuid_str) catch null;
        }
        if (parsed.value.account_uuid) |uuid_str| {
            creds.account_uuid = parseUuidString(uuid_str) catch null;
        }

        if (creds.canRefresh()) {
            log.info("Loaded encrypted credentials for: {s}", .{creds.username orelse "unknown"});
        }

        return creds;
    }

    /// Free credentials loaded by load()
    pub fn freeCredentials(self: *Self, creds: *StoredCredentials) void {
        if (creds.access_token) |token| self.allocator.free(token);
        if (creds.refresh_token) |token| self.allocator.free(token);
        if (creds.username) |name| self.allocator.free(name);
        creds.* = .{};
    }
};

/// Parse UUID string to bytes
fn parseUuidString(uuid_str: []const u8) ![16]u8 {
    if (uuid_str.len == 36) {
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
    }
    return error.InvalidLength;
}

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

test "encrypted credential store init" {
    const allocator = std.testing.allocator;

    var store = EncryptedCredentialStore.init(allocator);
    defer store.deinit();

    try std.testing.expectEqualStrings(DEFAULT_ENCRYPTED_FILE, store.file_path);
}

test "encrypt decrypt roundtrip" {
    const allocator = std.testing.allocator;

    var store = EncryptedCredentialStore.init(allocator);
    defer store.deinit();

    if (!store.isEncryptionAvailable()) {
        // Skip test if encryption not available
        return;
    }

    const plaintext = "test data for encryption";
    const encrypted = try store.encrypt(plaintext);
    defer allocator.free(encrypted);

    const decrypted = store.decrypt(encrypted) orelse return error.DecryptFailed;
    defer allocator.free(decrypted);

    try std.testing.expectEqualStrings(plaintext, decrypted);
}

test "stored credentials validation" {
    const empty_creds = StoredCredentials{};
    try std.testing.expect(!empty_creds.canRefresh());
    try std.testing.expect(!empty_creds.isAccessTokenValid());

    const refresh_creds = StoredCredentials{
        .refresh_token = "refresh",
    };
    try std.testing.expect(refresh_creds.canRefresh());

    const valid_creds = StoredCredentials{
        .access_token = "access",
        .expires_at = getTimestamp() + 3600,
    };
    try std.testing.expect(valid_creds.isAccessTokenValid());

    const expired_creds = StoredCredentials{
        .access_token = "access",
        .expires_at = getTimestamp() - 3600,
    };
    try std.testing.expect(!expired_creds.isAccessTokenValid());
}
