const std = @import("std");
const HttpClient = @import("http.zig").HttpClient;

const log = std.log.scoped(.session);

pub const Config = struct {
    pub const session_service_url = "https://sessions.hytale.com";
    pub const account_data_url = "https://account-data.hytale.com";
    // Match official Java server user agent format
    pub const user_agent = "HytaleServer/NoJar";
};

pub const GameProfile = struct {
    uuid: []const u8,
    username: []const u8,

    pub fn deinit(self: *GameProfile, allocator: std.mem.Allocator) void {
        allocator.free(self.uuid);
        allocator.free(self.username);
    }
};

pub const ProfilesResponse = struct {
    profiles: []GameProfile,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ProfilesResponse) void {
        for (self.profiles) |*p| {
            p.deinit(self.allocator);
        }
        self.allocator.free(self.profiles);
    }
};

pub const GameSessionResponse = struct {
    session_token: []const u8,
    identity_token: []const u8,
    expires_at: ?[]const u8,

    pub fn deinit(self: *GameSessionResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.session_token);
        allocator.free(self.identity_token);
        if (self.expires_at) |e| allocator.free(e);
    }
};

pub const SessionClient = struct {
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

    /// Get game profiles using OAuth access token
    pub fn getGameProfiles(self: *Self, access_token: []const u8) !?ProfilesResponse {
        var auth_header_buf: [2048]u8 = undefined;
        const auth_header = std.fmt.bufPrint(&auth_header_buf, "Bearer {s}", .{access_token}) catch return error.BufferTooSmall;

        const url = Config.account_data_url ++ "/my-account/get-profiles";

        const response = try self.http_client.get(url, auth_header, Config.user_agent);
        if (response) |resp| {
            defer self.allocator.free(resp);
            const result = try self.parseProfilesResponse(resp);
            return result;
        }
        return null;
    }

    /// Create game session for a profile
    pub fn createGameSession(self: *Self, access_token: []const u8, profile_uuid: []const u8) !?GameSessionResponse {
        var auth_header_buf: [2048]u8 = undefined;
        const auth_header = std.fmt.bufPrint(&auth_header_buf, "Bearer {s}", .{access_token}) catch return error.BufferTooSmall;

        var body_buf: [128]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buf, "{{\"uuid\":\"{s}\"}}", .{profile_uuid}) catch return error.BufferTooSmall;

        const url = Config.session_service_url ++ "/game-session/new";

        const response = try self.http_client.postJson(url, body, auth_header, Config.user_agent);
        if (response) |resp| {
            defer self.allocator.free(resp);
            const result = try self.parseGameSessionResponse(resp);
            return result;
        }
        return null;
    }

    /// Request auth grant for a connecting client
    pub fn requestAuthGrant(
        self: *Self,
        client_identity_token: []const u8,
        server_audience: []const u8,
        session_token: []const u8,
    ) !?[]const u8 {
        var auth_header_buf: [2048]u8 = undefined;
        const auth_header = std.fmt.bufPrint(&auth_header_buf, "Bearer {s}", .{session_token}) catch return error.BufferTooSmall;

        // Build JSON body
        var body_buf: [16384]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buf, "{{\"identityToken\":\"{s}\",\"aud\":\"{s}\"}}", .{ client_identity_token, server_audience }) catch return error.BufferTooSmall;

        const url = Config.session_service_url ++ "/server-join/auth-grant";

        const response = try self.http_client.postJson(url, body, auth_header, Config.user_agent);
        if (response) |resp| {
            defer self.allocator.free(resp);

            // Parse response
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, resp, .{}) catch |err| {
                log.err("Failed to parse auth grant response: {}", .{err});
                return null;
            };
            defer parsed.deinit();

            const obj = parsed.value.object;
            if (obj.get("authorizationGrant")) |value| {
                if (value == .string) {
                    return try self.allocator.dupe(u8, value.string);
                }
            }
        }
        return null;
    }

    /// Exchange client's auth grant for server access token
    pub fn exchangeAuthGrant(
        self: *Self,
        auth_grant: []const u8,
        cert_fingerprint: []const u8,
        session_token: []const u8,
    ) !?[]const u8 {
        var auth_header_buf: [2048]u8 = undefined;
        const auth_header = std.fmt.bufPrint(&auth_header_buf, "Bearer {s}", .{session_token}) catch return error.BufferTooSmall;

        var body_buf: [8192]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buf, "{{\"authorizationGrant\":\"{s}\",\"x509Fingerprint\":\"{s}\"}}", .{ auth_grant, cert_fingerprint }) catch return error.BufferTooSmall;

        const url = Config.session_service_url ++ "/server-join/auth-token";

        const response = try self.http_client.postJson(url, body, auth_header, Config.user_agent);
        if (response) |resp| {
            defer self.allocator.free(resp);

            // Parse response
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, resp, .{}) catch |err| {
                log.err("Failed to parse exchange response: {}", .{err});
                return null;
            };
            defer parsed.deinit();

            const obj = parsed.value.object;
            if (obj.get("accessToken")) |value| {
                if (value == .string) {
                    return try self.allocator.dupe(u8, value.string);
                }
            }
        }
        return null;
    }

    fn parseProfilesResponse(self: *Self, json_data: []const u8) !ProfilesResponse {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch |err| {
            log.err("Failed to parse profiles response: {}", .{err});
            return error.JsonParseError;
        };
        defer parsed.deinit();

        const obj = parsed.value.object;
        const profiles_arr = obj.get("profiles") orelse return error.MissingField;

        if (profiles_arr != .array) return error.InvalidFormat;

        var profiles: std.ArrayListUnmanaged(GameProfile) = .empty;
        errdefer {
            for (profiles.items) |*p| p.deinit(self.allocator);
            profiles.deinit(self.allocator);
        }

        for (profiles_arr.array.items) |profile| {
            if (profile != .object) continue;
            const p_obj = profile.object;

            const uuid = if (p_obj.get("uuid")) |v| blk: {
                if (v == .string) break :blk try self.allocator.dupe(u8, v.string);
                break :blk null;
            } else null;
            if (uuid == null) continue;

            const username = if (p_obj.get("username")) |v| blk: {
                if (v == .string) break :blk try self.allocator.dupe(u8, v.string);
                break :blk null;
            } else null;
            if (username == null) {
                self.allocator.free(uuid.?);
                continue;
            }

            try profiles.append(self.allocator, GameProfile{
                .uuid = uuid.?,
                .username = username.?,
            });
        }

        return ProfilesResponse{
            .profiles = try profiles.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    fn parseGameSessionResponse(self: *Self, json_data: []const u8) !GameSessionResponse {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch |err| {
            log.err("Failed to parse game session response: {}", .{err});
            return error.JsonParseError;
        };
        defer parsed.deinit();

        const obj = parsed.value.object;

        const session_token = if (obj.get("sessionToken")) |v| blk: {
            if (v == .string) break :blk try self.allocator.dupe(u8, v.string);
            break :blk null;
        } else null;
        if (session_token == null) return error.MissingField;
        errdefer self.allocator.free(session_token.?);

        const identity_token = if (obj.get("identityToken")) |v| blk: {
            if (v == .string) break :blk try self.allocator.dupe(u8, v.string);
            break :blk null;
        } else null;
        if (identity_token == null) {
            self.allocator.free(session_token.?);
            return error.MissingField;
        }
        errdefer self.allocator.free(identity_token.?);

        const expires_at = if (obj.get("expiresAt")) |v| blk: {
            if (v == .string) break :blk try self.allocator.dupe(u8, v.string);
            break :blk null;
        } else null;

        return GameSessionResponse{
            .session_token = session_token.?,
            .identity_token = identity_token.?,
            .expires_at = expires_at,
        };
    }
};
