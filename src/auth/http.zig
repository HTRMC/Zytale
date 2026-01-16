const std = @import("std");
const process = std.process;
const Io = std.Io;
const Threaded = Io.Threaded;

const log = std.log.scoped(.http);

/// Simple HTTP client using curl subprocess
/// This is a workaround for Zig 0.16's complex async HTTP client API
pub const HttpClient = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Make a POST request with form data
    pub fn postForm(self: *Self, url: []const u8, body: []const u8, user_agent: []const u8) !?[]u8 {
        return self.request("POST", url, body, "application/x-www-form-urlencoded", null, user_agent);
    }

    /// Make a POST request with JSON data
    pub fn postJson(self: *Self, url: []const u8, body: []const u8, auth_header: ?[]const u8, user_agent: []const u8) !?[]u8 {
        return self.request("POST", url, body, "application/json", auth_header, user_agent);
    }

    /// Make a GET request
    pub fn get(self: *Self, url: []const u8, auth_header: ?[]const u8, user_agent: []const u8) !?[]u8 {
        return self.request("GET", url, null, null, auth_header, user_agent);
    }

    fn request(
        self: *Self,
        method: []const u8,
        url: []const u8,
        body: ?[]const u8,
        content_type: ?[]const u8,
        auth_header: ?[]const u8,
        user_agent: []const u8,
    ) !?[]u8 {
        var args: std.ArrayListUnmanaged([]const u8) = .empty;
        defer args.deinit(self.allocator);

        // Track allocated strings for cleanup
        var ct_header: ?[]u8 = null;
        var auth_h: ?[]u8 = null;
        defer {
            if (ct_header) |h| self.allocator.free(h);
            if (auth_h) |h| self.allocator.free(h);
        }

        try args.append(self.allocator, "curl");
        try args.append(self.allocator, "-s"); // Silent mode
        try args.append(self.allocator, "-S"); // Show errors
        try args.append(self.allocator, "-X");
        try args.append(self.allocator, method);

        // User agent
        try args.append(self.allocator, "-A");
        try args.append(self.allocator, user_agent);

        // Content type
        if (content_type) |ct| {
            try args.append(self.allocator, "-H");
            ct_header = try std.fmt.allocPrint(self.allocator, "Content-Type: {s}", .{ct});
            try args.append(self.allocator, ct_header.?);
        }

        // Authorization header
        if (auth_header) |auth| {
            try args.append(self.allocator, "-H");
            auth_h = try std.fmt.allocPrint(self.allocator, "Authorization: {s}", .{auth});
            try args.append(self.allocator, auth_h.?);
        }

        // Body
        if (body) |b| {
            try args.append(self.allocator, "-d");
            try args.append(self.allocator, b);
        }

        // URL
        try args.append(self.allocator, url);

        // Create IO context for spawning process
        var threaded = Threaded.init(self.allocator, .{
            .environ = process.Environ.empty,
        });
        defer threaded.deinit();
        const io = threaded.io();

        // Spawn curl process
        var child = process.spawn(io, .{
            .argv = args.items,
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |err| {
            log.err("Failed to spawn curl: {}", .{err});
            return null;
        };

        // Read stdout
        var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
        var stderr_list: std.ArrayListUnmanaged(u8) = .empty;
        defer stderr_list.deinit(self.allocator);

        child.collectOutput(self.allocator, &stdout_list, &stderr_list, 1024 * 1024) catch |err| {
            log.err("Failed to read curl output: {}", .{err});
            stdout_list.deinit(self.allocator);
            return null;
        };

        // Wait for process
        const term = child.wait(io) catch |err| {
            log.err("Failed to wait for curl: {}", .{err});
            stdout_list.deinit(self.allocator);
            return null;
        };

        switch (term) {
            .exited => |code| {
                if (code != 0) {
                    log.err("curl failed with exit code {d}", .{code});
                    if (stderr_list.items.len > 0) {
                        log.err("stderr: {s}", .{stderr_list.items});
                    }
                    stdout_list.deinit(self.allocator);
                    return null;
                }
            },
            else => {
                log.err("curl terminated abnormally", .{});
                stdout_list.deinit(self.allocator);
                return null;
            },
        }

        return stdout_list.toOwnedSlice(self.allocator) catch {
            stdout_list.deinit(self.allocator);
            return null;
        };
    }
};
