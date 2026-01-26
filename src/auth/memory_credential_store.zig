/// Memory Credential Store
/// In-memory credential storage that does not persist across restarts
/// Implements the same interface as EncryptedCredentialStore
const std = @import("std");
const EncryptedStoredCredentials = @import("encrypted_credential_store.zig").StoredCredentials;

const log = std.log.scoped(.memory_credential_store);

/// Re-export StoredCredentials for convenience
pub const StoredCredentials = EncryptedStoredCredentials;

/// Memory-only credential store
/// Credentials are lost when the server stops
pub const MemoryCredentialStore = struct {
    allocator: std.mem.Allocator,

    /// Stored credentials (in memory only)
    credentials: ?StoredCredentials,

    /// Owned copies of credential strings
    access_token_owned: ?[]const u8,
    refresh_token_owned: ?[]const u8,
    username_owned: ?[]const u8,

    const Self = @This();

    /// Initialize memory store
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("Memory credential store initialized", .{});
        return .{
            .allocator = allocator,
            .credentials = null,
            .access_token_owned = null,
            .refresh_token_owned = null,
            .username_owned = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.clear();
    }

    /// Memory store is always available (no encryption key needed)
    pub fn isEncryptionAvailable(self: *const Self) bool {
        _ = self;
        return true;
    }

    /// Load credentials from memory
    /// Returns null if no credentials are stored
    pub fn load(self: *Self) ?StoredCredentials {
        if (self.credentials) |creds| {
            log.debug("Loaded credentials from memory for: {s}", .{creds.username orelse "unknown"});
            return creds;
        }
        log.debug("No credentials in memory", .{});
        return null;
    }

    /// Save credentials to memory
    pub fn save(self: *Self, creds: *const StoredCredentials) !void {
        // Clear any existing owned strings
        self.freeOwnedStrings();

        // Deep copy strings
        if (creds.access_token) |token| {
            self.access_token_owned = try self.allocator.dupe(u8, token);
        }
        if (creds.refresh_token) |token| {
            self.refresh_token_owned = try self.allocator.dupe(u8, token);
        }
        if (creds.username) |name| {
            self.username_owned = try self.allocator.dupe(u8, name);
        }

        // Store credentials with our owned copies
        self.credentials = StoredCredentials{
            .access_token = self.access_token_owned,
            .refresh_token = self.refresh_token_owned,
            .expires_at = creds.expires_at,
            .profile_uuid = creds.profile_uuid,
            .username = self.username_owned,
            .account_uuid = creds.account_uuid,
        };

        log.info("Saved credentials to memory for: {s}", .{creds.username orelse "unknown"});
    }

    /// Clear stored credentials
    pub fn clear(self: *Self) void {
        self.freeOwnedStrings();
        self.credentials = null;
        log.info("Cleared credentials from memory", .{});
    }

    /// Free owned string copies
    fn freeOwnedStrings(self: *Self) void {
        if (self.access_token_owned) |token| {
            self.allocator.free(token);
            self.access_token_owned = null;
        }
        if (self.refresh_token_owned) |token| {
            self.allocator.free(token);
            self.refresh_token_owned = null;
        }
        if (self.username_owned) |name| {
            self.allocator.free(name);
            self.username_owned = null;
        }
    }

    /// Free credentials returned by load()
    /// Note: For memory store, credentials point to internal storage,
    /// so this is a no-op (unlike EncryptedCredentialStore which allocates)
    pub fn freeCredentials(self: *Self, creds: *StoredCredentials) void {
        _ = self;
        creds.* = .{};
    }
};

test "memory credential store init" {
    const allocator = std.testing.allocator;

    var store = MemoryCredentialStore.init(allocator);
    defer store.deinit();

    try std.testing.expect(store.isEncryptionAvailable());
    try std.testing.expect(store.load() == null);
}

test "memory credential store save and load" {
    const allocator = std.testing.allocator;

    var store = MemoryCredentialStore.init(allocator);
    defer store.deinit();

    const creds = StoredCredentials{
        .access_token = "test_access",
        .refresh_token = "test_refresh",
        .expires_at = 12345,
        .username = "testuser",
    };

    try store.save(&creds);

    const loaded = store.load();
    try std.testing.expect(loaded != null);
    try std.testing.expectEqualStrings("test_access", loaded.?.access_token.?);
    try std.testing.expectEqualStrings("test_refresh", loaded.?.refresh_token.?);
    try std.testing.expectEqual(@as(i64, 12345), loaded.?.expires_at);
    try std.testing.expectEqualStrings("testuser", loaded.?.username.?);
}

test "memory credential store clear" {
    const allocator = std.testing.allocator;

    var store = MemoryCredentialStore.init(allocator);
    defer store.deinit();

    const creds = StoredCredentials{
        .access_token = "test_access",
        .refresh_token = "test_refresh",
    };

    try store.save(&creds);
    try std.testing.expect(store.load() != null);

    store.clear();
    try std.testing.expect(store.load() == null);
}
