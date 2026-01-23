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
};

/// Response from /server-join/auth-grant endpoint
pub const AuthGrantResponse = struct {
    authorization_grant: []const u8,
};

/// Response from /server-join/auth-token endpoint
pub const AuthTokenResponse = struct {
    access_token: []const u8,
};

/// Session Service HTTP Client
/// Handles communication with Hytale's Session Service for authentication
pub const SessionServiceClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .base_url = "https://sessions.hytale.com",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Nothing to clean up currently
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
};

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
