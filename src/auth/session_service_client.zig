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

        // Parse JSON response - wrapped in object with "owner" and "profiles"
        const parsed = std.json.parseFromSlice(struct {
            owner: []const u8,
            profiles: []const struct {
                uuid: []const u8,
                username: []const u8,
                createdAt: ?[]const u8 = null,
                entitlements: ?[]const []const u8 = null,
                nextNameChangeAt: ?[]const u8 = null,
                skin: ?[]const u8 = null,
            },
        }, self.allocator, response, .{ .ignore_unknown_fields = true }) catch {
            log.err("Failed to parse profiles response: {s}", .{response});
            return SessionServiceError.InvalidResponse;
        };
        defer parsed.deinit();

        log.debug("Account owner: {s}", .{parsed.value.owner});

        if (parsed.value.profiles.len == 0) {
            log.warn("No profiles found", .{});
            return SessionServiceError.NoProfiles;
        }

        // Convert to GameProfile array
        const profiles = self.allocator.alloc(GameProfile, parsed.value.profiles.len) catch
            return SessionServiceError.OutOfMemory;
        errdefer self.allocator.free(profiles);

        for (parsed.value.profiles, 0..) |profile, i| {
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

        // Parse JSON response - expiresAt comes as ISO 8601 string
        const parsed = std.json.parseFromSlice(struct {
            sessionToken: []const u8,
            identityToken: []const u8,
            expiresAt: []const u8,
        }, self.allocator, response, .{ .ignore_unknown_fields = true }) catch {
            log.err("Failed to parse session response: {s}", .{response});
            return SessionServiceError.InvalidResponse;
        };
        defer parsed.deinit();

        // Parse ISO 8601 timestamp to Unix epoch
        const expires_at = parseIso8601ToUnix(parsed.value.expiresAt) catch |err| {
            log.err("Failed to parse expiresAt timestamp '{s}': {}", .{ parsed.value.expiresAt, err });
            return SessionServiceError.InvalidResponse;
        };

        const result = GameSessionResponse{
            .session_token = self.allocator.dupe(u8, parsed.value.sessionToken) catch
                return SessionServiceError.OutOfMemory,
            .identity_token = self.allocator.dupe(u8, parsed.value.identityToken) catch
                return SessionServiceError.OutOfMemory,
            .expires_at = expires_at,
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
            return SessionServiceError.AuthenticationFailed;
        }

        if (result.status != .ok) {
            log.err("Request failed with status: {}", .{result.status});
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

/// Parse ISO 8601 timestamp to Unix epoch seconds
/// Handles format: "2026-01-23T20:43:39.930178155Z" or "2026-01-23T20:43:39Z"
fn parseIso8601ToUnix(iso_str: []const u8) !i64 {
    // Minimum format: YYYY-MM-DDTHH:MM:SSZ (20 chars)
    if (iso_str.len < 20) return error.InvalidFormat;

    // Parse date components
    const year = std.fmt.parseInt(i32, iso_str[0..4], 10) catch return error.InvalidYear;
    if (iso_str[4] != '-') return error.InvalidFormat;
    const month = std.fmt.parseInt(u8, iso_str[5..7], 10) catch return error.InvalidMonth;
    if (iso_str[7] != '-') return error.InvalidFormat;
    const day = std.fmt.parseInt(u8, iso_str[8..10], 10) catch return error.InvalidDay;
    if (iso_str[10] != 'T') return error.InvalidFormat;

    // Parse time components
    const hour = std.fmt.parseInt(u8, iso_str[11..13], 10) catch return error.InvalidHour;
    if (iso_str[13] != ':') return error.InvalidFormat;
    const minute = std.fmt.parseInt(u8, iso_str[14..16], 10) catch return error.InvalidMinute;
    if (iso_str[16] != ':') return error.InvalidFormat;
    const second = std.fmt.parseInt(u8, iso_str[17..19], 10) catch return error.InvalidSecond;
    // Skip fractional seconds and 'Z' suffix - we only need second precision

    // Validate ranges
    if (month < 1 or month > 12) return error.InvalidMonth;
    if (day < 1 or day > 31) return error.InvalidDay;
    if (hour > 23) return error.InvalidHour;
    if (minute > 59) return error.InvalidMinute;
    if (second > 59) return error.InvalidSecond;

    // Convert to Unix timestamp
    // Days from epoch (1970-01-01) to start of year
    const years_since_epoch = year - 1970;
    var days: i64 = years_since_epoch * 365;

    // Add leap years (simplified - works for 1970-2099)
    days += @divFloor(years_since_epoch + 1, 4);

    // Days in months (non-leap year)
    const days_in_months = [_]u8{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    for (1..month) |m| {
        days += days_in_months[m];
    }

    // Add extra day for leap year if past February
    const is_leap = (@mod(year, 4) == 0 and @mod(year, 100) != 0) or @mod(year, 400) == 0;
    if (is_leap and month > 2) {
        days += 1;
    }

    // Add days in current month
    days += day - 1;

    // Convert to seconds
    const timestamp: i64 = days * 86400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);

    return timestamp;
}

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

test "iso 8601 parsing" {
    // Test with fractional seconds (like the API returns)
    const ts1 = try parseIso8601ToUnix("2026-01-23T20:43:39.930178155Z");
    // 2026-01-23 20:43:39 UTC
    // Days from 1970-01-01 to 2026-01-23:
    // 56 years = 56*365 + 14 leap days = 20454 days to 2026-01-01
    // + 22 days (Jan 23) = 20476 days
    // 20476 * 86400 + 20*3600 + 43*60 + 39 = 1769293419
    try std.testing.expectEqual(@as(i64, 1769293419), ts1);

    // Test without fractional seconds
    const ts2 = try parseIso8601ToUnix("2026-01-23T20:43:39Z");
    try std.testing.expectEqual(@as(i64, 1769293419), ts2);

    // Test epoch
    const ts3 = try parseIso8601ToUnix("1970-01-01T00:00:00Z");
    try std.testing.expectEqual(@as(i64, 0), ts3);
}
