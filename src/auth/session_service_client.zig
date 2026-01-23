/// Hytale Session Service Client
/// Makes HTTP requests to sessions.hytale.com for authentication token exchange
const std = @import("std");

const log = std.log.scoped(.session_service);

/// Error types for Session Service operations
pub const SessionServiceError = error{
    /// Failed to connect to Session Service
    ConnectionFailed,
    /// HTTP request failed
    RequestFailed,
    /// Invalid JSON response
    InvalidResponse,
    /// Session Service returned an error
    ServiceError,
    /// Authentication failed (401/403)
    AuthenticationFailed,
    /// Out of memory
    OutOfMemory,
    /// URL parse error
    InvalidUrl,
    /// No profiles found
    NoProfiles,
};

/// Response from /server-join/auth-grant endpoint
pub const AuthGrantResponse = struct {
    authorization_grant: []const u8,
};

/// Response from /server-join/auth-token endpoint
pub const AuthTokenResponse = struct {
    access_token: []const u8,
};

/// Game profile from account-data service
pub const GameProfile = struct {
    uuid: [16]u8,
    username: []const u8,
};

/// Response from /game-session/new endpoint
pub const GameSessionResponse = struct {
    session_token: []const u8,
    identity_token: []const u8,
    expires_at: i64,
};

/// Session Service HTTP Client
/// Handles communication with Hytale's Session Service for authentication
pub const SessionServiceClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    account_data_url: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .base_url = "https://sessions.hytale.com",
            .account_data_url = "https://account-data.hytale.com",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Nothing to clean up currently
    }

    /// GET https://account-data.hytale.com/my-account/get-profiles
    /// Fetch game profiles associated with the authenticated account
    pub fn getGameProfiles(self: *Self, access_token: []const u8) SessionServiceError![]GameProfile {
        log.info("Fetching game profiles...", .{});

        const response = self.makeGetRequest(
            "/my-account/get-profiles",
            self.account_data_url,
            access_token,
        ) catch |err| {
            log.err("Failed to fetch profiles: {}", .{err});
            return err;
        };
        defer self.allocator.free(response);

        // Parse JSON response (array of profiles)
        const parsed = std.json.parseFromSlice([]struct {
            uuid: []const u8,
            username: []const u8,
        }, self.allocator, response, .{}) catch {
            log.err("Failed to parse profiles response: {s}", .{response});
            return SessionServiceError.InvalidResponse;
        };
        defer parsed.deinit();

        if (parsed.value.len == 0) {
            log.warn("No profiles found", .{});
            return SessionServiceError.NoProfiles;
        }

        // Convert to GameProfile array
        const profiles = self.allocator.alloc(GameProfile, parsed.value.len) catch
            return SessionServiceError.OutOfMemory;
        errdefer self.allocator.free(profiles);

        for (parsed.value, 0..) |profile, i| {
            // Parse UUID string to bytes
            profiles[i].uuid = parseUuidString(profile.uuid) catch {
                log.err("Invalid UUID format: {s}", .{profile.uuid});
                return SessionServiceError.InvalidResponse;
            };
            profiles[i].username = self.allocator.dupe(u8, profile.username) catch
                return SessionServiceError.OutOfMemory;
        }

        log.info("Found {d} profile(s)", .{profiles.len});
        return profiles;
    }

    /// Free profiles returned by getGameProfiles
    pub fn freeProfiles(self: *Self, profiles: []GameProfile) void {
        for (profiles) |profile| {
            self.allocator.free(profile.username);
        }
        self.allocator.free(profiles);
    }

    /// POST https://sessions.hytale.com/game-session/new
    /// Create a new game session for the selected profile
    pub fn createGameSession(
        self: *Self,
        access_token: []const u8,
        profile_uuid: [16]u8,
    ) SessionServiceError!GameSessionResponse {
        log.info("Creating game session...", .{});

        // Format UUID as string for JSON body
        const uuid_str = uuidToString(profile_uuid);

        // Build JSON request body
        const body = std.fmt.allocPrint(self.allocator, "{{\"uuid\":\"{s}\"}}", .{uuid_str}) catch
            return SessionServiceError.OutOfMemory;
        defer self.allocator.free(body);

        const response = self.makePostRequest(
            "/game-session/new",
            body,
            access_token,
        ) catch |err| {
            log.err("Failed to create game session: {}", .{err});
            return err;
        };
        defer self.allocator.free(response);

        // Parse JSON response
        const parsed = std.json.parseFromSlice(struct {
            sessionToken: []const u8,
            identityToken: []const u8,
            expiresAt: i64,
        }, self.allocator, response, .{}) catch {
            log.err("Failed to parse session response: {s}", .{response});
            return SessionServiceError.InvalidResponse;
        };
        defer parsed.deinit();

        const result = GameSessionResponse{
            .session_token = self.allocator.dupe(u8, parsed.value.sessionToken) catch
                return SessionServiceError.OutOfMemory,
            .identity_token = self.allocator.dupe(u8, parsed.value.identityToken) catch
                return SessionServiceError.OutOfMemory,
            .expires_at = parsed.value.expiresAt,
        };

        log.info("Game session created (expires at {d})", .{result.expires_at});
        return result;
    }

    /// Free a GameSessionResponse
    pub fn freeGameSession(self: *Self, session: *GameSessionResponse) void {
        self.allocator.free(session.session_token);
        self.allocator.free(session.identity_token);
    }

    /// POST /server-join/auth-grant
    /// Request authorization grant from Session Service
    ///
    /// HTTP Request:
    ///   POST https://sessions.hytale.com/server-join/auth-grant
    ///   Authorization: Bearer <server_session_token>
    ///   Content-Type: application/json
    ///   Body: {"identityToken":"<client_jwt>","aud":"<server_audience>"}
    ///
    /// Response: {"authorizationGrant": "<auth_grant_string>"}
    pub fn requestAuthGrant(
        self: *Self,
        client_identity_token: []const u8,
        server_audience: []const u8,
        bearer_token: []const u8,
    ) SessionServiceError![]u8 {
        log.info("Requesting auth grant from Session Service...", .{});
        log.debug("  audience: {s}", .{server_audience});
        log.debug("  identity_token length: {d}", .{client_identity_token.len});

        // Build JSON request body
        const body = buildAuthGrantRequestBody(self.allocator, client_identity_token, server_audience) catch
            return SessionServiceError.OutOfMemory;
        defer self.allocator.free(body);

        // Make HTTP request
        const response = self.makePostRequest(
            "/server-join/auth-grant",
            body,
            bearer_token,
        ) catch |err| {
            log.err("Failed to request auth grant: {}", .{err});
            return err;
        };
        defer self.allocator.free(response);

        // Parse JSON response
        const parsed = std.json.parseFromSlice(
            struct { authorizationGrant: []const u8 },
            self.allocator,
            response,
            .{},
        ) catch {
            log.err("Failed to parse auth grant response", .{});
            return SessionServiceError.InvalidResponse;
        };
        defer parsed.deinit();

        const result = self.allocator.dupe(u8, parsed.value.authorizationGrant) catch
            return SessionServiceError.OutOfMemory;

        log.info("Received authorization grant (length={d})", .{result.len});
        return result;
    }

    /// POST /server-join/auth-token
    /// Exchange authorization grant for server access token
    ///
    /// HTTP Request:
    ///   POST https://sessions.hytale.com/server-join/auth-token
    ///   Authorization: Bearer <server_session_token>
    ///   Content-Type: application/json
    ///   Body: {"authorizationGrant":"<auth_grant>","x509Fingerprint":"<cert_fingerprint>"}
    ///
    /// Response: {"accessToken": "<server_access_token>"}
    pub fn exchangeAuthGrant(
        self: *Self,
        authorization_grant: []const u8,
        x509_fingerprint: []const u8,
        bearer_token: []const u8,
    ) SessionServiceError![]u8 {
        log.info("Exchanging auth grant for server access token...", .{});
        log.debug("  auth_grant length: {d}", .{authorization_grant.len});
        log.debug("  x509_fingerprint: {s}", .{x509_fingerprint});

        // Build JSON request body
        const body = buildAuthTokenRequestBody(self.allocator, authorization_grant, x509_fingerprint) catch
            return SessionServiceError.OutOfMemory;
        defer self.allocator.free(body);

        // Make HTTP request
        const response = self.makePostRequest(
            "/server-join/auth-token",
            body,
            bearer_token,
        ) catch |err| {
            log.err("Failed to exchange auth grant: {}", .{err});
            return err;
        };
        defer self.allocator.free(response);

        // Parse JSON response
        const parsed = std.json.parseFromSlice(
            struct { accessToken: []const u8 },
            self.allocator,
            response,
            .{},
        ) catch {
            log.err("Failed to parse auth token response", .{});
            return SessionServiceError.InvalidResponse;
        };
        defer parsed.deinit();

        const result = self.allocator.dupe(u8, parsed.value.accessToken) catch
            return SessionServiceError.OutOfMemory;

        log.info("Received server access token (length={d})", .{result.len});
        return result;
    }

    /// Make a POST request to the Session Service
    fn makePostRequest(
        self: *Self,
        path: []const u8,
        body: []const u8,
        bearer_token: []const u8,
    ) SessionServiceError![]u8 {
        // Build full URL
        const url = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path }) catch
            return SessionServiceError.OutOfMemory;
        defer self.allocator.free(url);

        log.info("POST {s}", .{url});
        log.debug("Body: {s}", .{body});

        // Get I/O handle for async operations
        const io = std.Io.Threaded.global_single_threaded.io();

        // Create HTTP client
        var client = std.http.Client{
            .allocator = self.allocator,
            .io = io,
        };
        defer client.deinit();

        // Build authorization header value
        const auth_header_value = std.fmt.allocPrint(self.allocator, "Bearer {s}", .{bearer_token}) catch
            return SessionServiceError.OutOfMemory;
        defer self.allocator.free(auth_header_value);

        // Create an allocating writer for the response body
        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_writer.deinit();

        // Perform the fetch request
        const result = client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header_value },
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .response_writer = &response_writer.writer,
        }) catch |err| {
            log.err("HTTP request failed: {}", .{err});
            return SessionServiceError.ConnectionFailed;
        };

        // Check status code
        if (result.status == .unauthorized or result.status == .forbidden) {
            log.err("Session Service authentication failed: {}", .{result.status});
            response_writer.deinit();
            return SessionServiceError.AuthenticationFailed;
        }

        if (result.status != .ok) {
            log.err("Session Service returned error status: {}", .{result.status});
            response_writer.deinit();
            return SessionServiceError.ServiceError;
        }

        // Get the response body - transfer ownership via toArrayList then toOwnedSlice
        var array_list = response_writer.toArrayList();
        const response_body = array_list.toOwnedSlice(self.allocator) catch {
            array_list.deinit(self.allocator);
            return SessionServiceError.OutOfMemory;
        };

        log.debug("Response ({d} bytes): {s}", .{ response_body.len, response_body });
        return response_body;
    }

    /// Make a GET request to the Session Service
    fn makeGetRequest(
        self: *Self,
        path: []const u8,
        base: []const u8,
        bearer_token: []const u8,
    ) SessionServiceError![]u8 {
        // Build full URL
        const url = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, path }) catch
            return SessionServiceError.OutOfMemory;
        defer self.allocator.free(url);

        log.info("GET {s}", .{url});

        // Get I/O handle for async operations
        const io = std.Io.Threaded.global_single_threaded.io();

        // Create HTTP client
        var client = std.http.Client{
            .allocator = self.allocator,
            .io = io,
        };
        defer client.deinit();

        // Build authorization header value
        const auth_header_value = std.fmt.allocPrint(self.allocator, "Bearer {s}", .{bearer_token}) catch
            return SessionServiceError.OutOfMemory;
        defer self.allocator.free(auth_header_value);

        // Create an allocating writer for the response body
        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_writer.deinit();

        // Perform the fetch request
        const result = client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header_value },
            },
            .response_writer = &response_writer.writer,
        }) catch |err| {
            log.err("HTTP request failed: {}", .{err});
            return SessionServiceError.ConnectionFailed;
        };

        // Check status code
        if (result.status == .unauthorized or result.status == .forbidden) {
            log.err("Authentication failed: {}", .{result.status});
            response_writer.deinit();
            return SessionServiceError.AuthenticationFailed;
        }

        if (result.status != .ok) {
            log.err("Request failed with status: {}", .{result.status});
            response_writer.deinit();
            return SessionServiceError.ServiceError;
        }

        // Get the response body
        var array_list = response_writer.toArrayList();
        const response_body = array_list.toOwnedSlice(self.allocator) catch {
            array_list.deinit(self.allocator);
            return SessionServiceError.OutOfMemory;
        };

        log.debug("Response ({d} bytes): {s}", .{ response_body.len, response_body });
        return response_body;
    }
};

/// Parse UUID string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) to 16 bytes
fn parseUuidString(uuid_str: []const u8) ![16]u8 {
    if (uuid_str.len != 36) return error.InvalidLength;

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
        i += 1; // Skip next char as we consumed it
    }

    if (byte_idx != 16) return error.InvalidLength;
    return result;
}

/// Format UUID bytes as string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
fn uuidToString(uuid: [16]u8) [36]u8 {
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

/// Build JSON body for auth grant request: {"identityToken":"...","aud":"..."}
fn buildAuthGrantRequestBody(allocator: std.mem.Allocator, identity_token: []const u8, audience: []const u8) ![]u8 {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer list.deinit(allocator);

    try list.appendSlice(allocator, "{\"identityToken\":\"");
    try appendJsonEscaped(allocator, &list, identity_token);
    try list.appendSlice(allocator, "\",\"aud\":\"");
    try appendJsonEscaped(allocator, &list, audience);
    try list.appendSlice(allocator, "\"}");

    return list.toOwnedSlice(allocator);
}

/// Build JSON body for auth token request: {"authorizationGrant":"...","x509Fingerprint":"..."}
fn buildAuthTokenRequestBody(allocator: std.mem.Allocator, auth_grant: []const u8, x509_fingerprint: []const u8) ![]u8 {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer list.deinit(allocator);

    try list.appendSlice(allocator, "{\"authorizationGrant\":\"");
    try appendJsonEscaped(allocator, &list, auth_grant);
    try list.appendSlice(allocator, "\",\"x509Fingerprint\":\"");
    try appendJsonEscaped(allocator, &list, x509_fingerprint);
    try list.appendSlice(allocator, "\"}");

    return list.toOwnedSlice(allocator);
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

test "session service client init" {
    const allocator = std.testing.allocator;
    var client = SessionServiceClient.init(allocator);
    defer client.deinit();

    try std.testing.expectEqualStrings("https://sessions.hytale.com", client.base_url);
}

test "build auth grant request body" {
    const allocator = std.testing.allocator;

    const body = try buildAuthGrantRequestBody(allocator, "token123", "audience456");
    defer allocator.free(body);

    try std.testing.expectEqualStrings("{\"identityToken\":\"token123\",\"aud\":\"audience456\"}", body);
}

test "build auth token request body" {
    const allocator = std.testing.allocator;

    const body = try buildAuthTokenRequestBody(allocator, "grant123", "fingerprint456");
    defer allocator.free(body);

    try std.testing.expectEqualStrings("{\"authorizationGrant\":\"grant123\",\"x509Fingerprint\":\"fingerprint456\"}", body);
}

test "uuid string parsing" {
    const uuid_str = "550e8400-e29b-41d4-a716-446655440000";
    const uuid_bytes = try parseUuidString(uuid_str);

    try std.testing.expectEqual(@as(u8, 0x55), uuid_bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), uuid_bytes[1]);
    try std.testing.expectEqual(@as(u8, 0x84), uuid_bytes[2]);
    try std.testing.expectEqual(@as(u8, 0x00), uuid_bytes[3]);
}

test "uuid to string" {
    const uuid_bytes = [16]u8{ 0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4, 0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00 };
    const uuid_str = uuidToString(uuid_bytes);

    try std.testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", &uuid_str);
}
