const std = @import("std");
const HttpClient = @import("http.zig").HttpClient;

const log = std.log.scoped(.oauth);

// OAuth configuration
pub const Config = struct {
    pub const client_id = "hytale-server";
    pub const scopes = "openid offline auth:server";
    // Match official Java server user agent format
    pub const user_agent = "HytaleServer/NoJar";
    pub const device_auth_url = "https://oauth.accounts.hytale.com/oauth2/device/auth";
    pub const token_url = "https://oauth.accounts.hytale.com/oauth2/token";
};

pub const DeviceAuthResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    verification_uri_complete: ?[]const u8,
    expires_in: u32,
    interval: u32,

    pub fn deinit(self: *DeviceAuthResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.device_code);
        allocator.free(self.user_code);
        allocator.free(self.verification_uri);
        if (self.verification_uri_complete) |v| allocator.free(v);
    }
};

pub const TokenResponse = struct {
    access_token: ?[]const u8,
    refresh_token: ?[]const u8,
    id_token: ?[]const u8,
    error_code: ?[]const u8,
    expires_in: u32,

    pub fn isSuccess(self: *const TokenResponse) bool {
        return self.error_code == null and self.access_token != null;
    }

    pub fn isPending(self: *const TokenResponse) bool {
        if (self.error_code) |err| {
            return std.mem.eql(u8, err, "authorization_pending");
        }
        return false;
    }

    pub fn deinit(self: *TokenResponse, allocator: std.mem.Allocator) void {
        if (self.access_token) |t| allocator.free(t);
        if (self.refresh_token) |t| allocator.free(t);
        if (self.id_token) |t| allocator.free(t);
        if (self.error_code) |e| allocator.free(e);
    }
};

pub const OAuthClient = struct {
    allocator: std.mem.Allocator,
    http_client: HttpClient,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .http_client = HttpClient.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
    }

    /// Request device authorization - returns device code and user code
    pub fn requestDeviceAuthorization(self: *Self) !DeviceAuthResponse {
        const body = "client_id=" ++ Config.client_id ++ "&scope=" ++ Config.scopes;

        const response = try self.http_client.postForm(Config.device_auth_url, body, Config.user_agent) orelse {
            log.err("Device auth failed: no response", .{});
            return error.DeviceAuthFailed;
        };
        defer self.allocator.free(response);

        // Parse JSON response
        return self.parseDeviceAuthResponse(response);
    }

    /// Poll for device token
    pub fn pollDeviceToken(self: *Self, device_code: []const u8) !?TokenResponse {
        // Build request body
        var body_buf: [512]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buf, "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id={s}&device_code={s}", .{ Config.client_id, device_code }) catch return error.BufferTooSmall;

        const response = try self.http_client.postForm(Config.token_url, body, Config.user_agent);
        if (response) |resp| {
            defer self.allocator.free(resp);
            const token_resp = try self.parseTokenResponse(resp);
            return token_resp;
        }
        return null;
    }

    /// Refresh tokens
    pub fn refreshTokens(self: *Self, refresh_token: []const u8) !?TokenResponse {
        var body_buf: [2048]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buf, "grant_type=refresh_token&client_id={s}&refresh_token={s}", .{ Config.client_id, refresh_token }) catch return error.BufferTooSmall;

        const response = try self.http_client.postForm(Config.token_url, body, Config.user_agent);
        if (response) |resp| {
            defer self.allocator.free(resp);
            const token_resp = try self.parseTokenResponse(resp);
            return token_resp;
        }
        return null;
    }

    fn parseDeviceAuthResponse(self: *Self, json_data: []const u8) !DeviceAuthResponse {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch |err| {
            log.err("Failed to parse device auth response: {}", .{err});
            return error.JsonParseError;
        };
        defer parsed.deinit();

        const obj = parsed.value.object;

        const device_code = try self.dupeJsonString(obj, "device_code") orelse return error.MissingField;
        errdefer self.allocator.free(device_code);

        const user_code = try self.dupeJsonString(obj, "user_code") orelse return error.MissingField;
        errdefer self.allocator.free(user_code);

        const verification_uri = try self.dupeJsonString(obj, "verification_uri") orelse return error.MissingField;
        errdefer self.allocator.free(verification_uri);

        const verification_uri_complete = try self.dupeJsonString(obj, "verification_uri_complete");

        const expires_in = if (obj.get("expires_in")) |v| @as(u32, @intCast(v.integer)) else 600;
        const interval = if (obj.get("interval")) |v| @as(u32, @intCast(v.integer)) else 5;

        return DeviceAuthResponse{
            .device_code = device_code,
            .user_code = user_code,
            .verification_uri = verification_uri,
            .verification_uri_complete = verification_uri_complete,
            .expires_in = expires_in,
            .interval = interval,
        };
    }

    fn parseTokenResponse(self: *Self, json_data: []const u8) !TokenResponse {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch |err| {
            log.err("Failed to parse token response: {}", .{err});
            return error.JsonParseError;
        };
        defer parsed.deinit();

        const obj = parsed.value.object;

        const access_token = try self.dupeJsonString(obj, "access_token");
        const refresh_token = try self.dupeJsonString(obj, "refresh_token");
        const id_token = try self.dupeJsonString(obj, "id_token");
        const error_code = try self.dupeJsonString(obj, "error");
        const expires_in = if (obj.get("expires_in")) |v| @as(u32, @intCast(v.integer)) else 0;

        return TokenResponse{
            .access_token = access_token,
            .refresh_token = refresh_token,
            .id_token = id_token,
            .error_code = error_code,
            .expires_in = expires_in,
        };
    }

    fn dupeJsonString(self: *Self, obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
        if (obj.get(key)) |value| {
            if (value == .string) {
                return try self.allocator.dupe(u8, value.string);
            }
        }
        return null;
    }
};
