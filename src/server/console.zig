/// Server Console
/// Handles stdin command processing for server administration
const std = @import("std");
const builtin = @import("builtin");
const auth = @import("../auth/auth.zig");

const log = std.log.scoped(.console);

/// Get current Unix timestamp using std.Io
fn getTimestamp() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io) catch return 0;
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

/// Console command handler callback
pub const CommandHandler = *const fn (console: *Console, args: []const u8) void;

/// Registered command
const Command = struct {
    name: []const u8,
    description: []const u8,
    handler: CommandHandler,
};

/// Server console for processing admin commands
pub const Console = struct {
    allocator: std.mem.Allocator,
    auth_manager: *auth.AuthManager,
    credentials: *auth.ServerCredentials,
    running: std.atomic.Value(bool),
    thread: ?std.Thread,

    const Self = @This();

    /// Initialize console
    pub fn init(
        allocator: std.mem.Allocator,
        auth_manager: *auth.AuthManager,
        credentials: *auth.ServerCredentials,
    ) Self {
        return .{
            .allocator = allocator,
            .auth_manager = auth_manager,
            .credentials = credentials,
            .running = std.atomic.Value(bool).init(false),
            .thread = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
    }

    /// Start console thread
    pub fn start(self: *Self) !void {
        if (self.running.load(.acquire)) {
            return;
        }

        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, consoleThread, .{self});
    }

    /// Stop console thread
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
        if (self.thread) |thread| {
            // Note: We can't cleanly interrupt stdin reads
            // The thread will exit on next input or when program exits
            thread.detach();
            self.thread = null;
        }
    }

    /// Console thread entry point
    fn consoleThread(self: *Self) void {
        log.info("Console started. Type /help for commands.", .{});

        var buf: [1024]u8 = undefined;

        while (self.running.load(.acquire)) {
            // Read line from stdin using low-level read
            const line = readStdinLine(&buf) catch |err| {
                if (err == error.EndOfStream) {
                    log.info("Console: EOF received", .{});
                    break;
                }
                continue;
            };

            // Trim whitespace
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            // Process command
            self.processLine(trimmed);
        }

        log.info("Console stopped.", .{});
    }

    /// Read a line from stdin (platform-specific)
    fn readStdinLine(buf: []u8) ![]u8 {
        if (builtin.os.tag == .windows) {
            const windows = std.os.windows;
            const handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch return error.StdinUnavailable;

            var bytes_read: u32 = 0;
            var i: usize = 0;

            while (i < buf.len - 1) {
                var char_buf: [1]u8 = undefined;
                if (windows.kernel32.ReadFile(handle, &char_buf, 1, &bytes_read, null) == windows.FALSE) {
                    return error.ReadFailed;
                }
                if (bytes_read == 0) return error.EndOfStream;

                const c = char_buf[0];
                if (c == '\n') break;
                if (c == '\r') continue; // Skip CR

                buf[i] = c;
                i += 1;
            }

            return buf[0..i];
        } else {
            // POSIX - use std.posix
            const fd: std.posix.fd_t = 0; // stdin
            var i: usize = 0;

            while (i < buf.len - 1) {
                const bytes_read = std.posix.read(fd, buf[i..][0..1]) catch return error.ReadFailed;
                if (bytes_read == 0) return error.EndOfStream;

                const c = buf[i];
                if (c == '\n') break;

                i += 1;
            }

            return buf[0..i];
        }
    }

    /// Process a single command line
    pub fn processLine(self: *Self, line: []const u8) void {
        // Check if it's a command (starts with /)
        if (line.len == 0) return;

        if (line[0] != '/') {
            std.debug.print("Unknown input. Type /help for commands.\n", .{});
            return;
        }

        // Parse command and arguments
        const cmd_line = line[1..]; // Skip the /
        var iter = std.mem.splitScalar(u8, cmd_line, ' ');
        const cmd = iter.next() orelse return;

        // Get remaining arguments
        const args_start = if (iter.index) |idx| idx else cmd_line.len;
        const args = std.mem.trim(u8, cmd_line[args_start..], " ");

        // Dispatch command
        if (std.mem.eql(u8, cmd, "help")) {
            self.cmdHelp();
        } else if (std.mem.eql(u8, cmd, "auth")) {
            self.cmdAuth(args);
        } else if (std.mem.eql(u8, cmd, "status")) {
            self.cmdStatus();
        } else if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "stop")) {
            self.cmdQuit();
        } else {
            std.debug.print("Unknown command: /{s}\n", .{cmd});
            std.debug.print("Type /help for available commands.\n", .{});
        }
    }

    /// /help command
    fn cmdHelp(self: *Self) void {
        _ = self;
        std.debug.print("\n", .{});
        std.debug.print("=== Zytale Server Commands ===\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("  /help                        Show this help message\n", .{});
        std.debug.print("  /status                      Show server status\n", .{});
        std.debug.print("  /auth status                 Show authentication status\n", .{});
        std.debug.print("  /auth login device           Start OAuth device flow login\n", .{});
        std.debug.print("  /auth logout                 Clear stored credentials\n", .{});
        std.debug.print("  /auth refresh                Refresh expired tokens\n", .{});
        std.debug.print("  /auth select <username>      Select a profile by username\n", .{});
        std.debug.print("  /auth profiles               List available game profiles\n", .{});
        std.debug.print("  /auth persistence            Show current storage type\n", .{});
        std.debug.print("  /auth persistence <type>     Switch storage (memory|encrypted)\n", .{});
        std.debug.print("  /quit                        Stop the server\n", .{});
        std.debug.print("\n", .{});
    }

    /// /auth command
    fn cmdAuth(self: *Self, args: []const u8) void {
        var iter = std.mem.splitScalar(u8, args, ' ');
        const subcmd = iter.next() orelse {
            std.debug.print("Usage: /auth <status|login|logout|refresh|select|profiles|persistence>\n", .{});
            return;
        };

        if (std.mem.eql(u8, subcmd, "status")) {
            self.cmdAuthStatus();
        } else if (std.mem.eql(u8, subcmd, "login")) {
            const method = iter.next() orelse "device";
            if (std.mem.eql(u8, method, "device")) {
                self.cmdAuthLoginDevice();
            } else {
                std.debug.print("Unknown login method: {s}\n", .{method});
                std.debug.print("Available methods: device\n", .{});
            }
        } else if (std.mem.eql(u8, subcmd, "logout")) {
            self.cmdAuthLogout();
        } else if (std.mem.eql(u8, subcmd, "refresh")) {
            self.cmdAuthRefresh();
        } else if (std.mem.eql(u8, subcmd, "select")) {
            const username = iter.next() orelse {
                std.debug.print("Usage: /auth select <username>\n", .{});
                return;
            };
            self.cmdAuthSelect(username);
        } else if (std.mem.eql(u8, subcmd, "profiles")) {
            self.cmdAuthProfiles();
        } else if (std.mem.eql(u8, subcmd, "persistence")) {
            const storage_type = iter.next();
            self.cmdAuthPersistence(storage_type);
        } else {
            std.debug.print("Unknown auth command: {s}\n", .{subcmd});
            std.debug.print("Usage: /auth <status|login|logout|refresh|select|profiles|persistence>\n", .{});
        }
    }

    /// /auth status command
    fn cmdAuthStatus(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("=== Authentication Status ===\n", .{});
        std.debug.print("  Mode: {s}\n", .{self.auth_manager.getAuthMode().toString()});
        std.debug.print("  State: {s}\n", .{self.auth_manager.getAuthStatus()});
        std.debug.print("  Storage: {s}\n", .{self.auth_manager.getStoreType().toString()});

        const expiry = self.auth_manager.getSecondsUntilExpiry();
        if (expiry > 0) {
            const minutes = @divFloor(expiry, 60);
            const seconds = @mod(expiry, 60);
            std.debug.print("  Token expires in: {d}m {d}s\n", .{ minutes, seconds });
        } else if (self.auth_manager.isAuthenticated()) {
            std.debug.print("  Token expires in: EXPIRED\n", .{});
        }

        self.credentials.logStatus();
        std.debug.print("\n", .{});
    }

    /// /auth login device command
    fn cmdAuthLoginDevice(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("Starting device authorization flow...\n", .{});

        // Start device flow
        const auth_info = self.auth_manager.startDeviceFlow() catch |err| {
            std.debug.print("Failed to start device flow: {}\n", .{err});
            if (self.auth_manager.getErrorMessage()) |msg| {
                std.debug.print("  {s}\n", .{msg});
            }
            return;
        };

        std.debug.print("\n", .{});
        std.debug.print("========================================\n", .{});
        std.debug.print("  Visit: {s}\n", .{auth_info.verification_uri});
        std.debug.print("  Enter code: {s}\n", .{auth_info.user_code});
        std.debug.print("========================================\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Waiting for authorization...\n", .{});

        // Poll for token
        while (self.auth_manager.getState() == .polling) {
            if (self.auth_manager.pollDeviceFlow()) |got_token| {
                if (got_token) break;
            } else |err| {
                std.debug.print("Authentication failed: {}\n", .{err});
                if (self.auth_manager.getErrorMessage()) |msg| {
                    std.debug.print("  {s}\n", .{msg});
                }
                return;
            }

            // Wait before next poll
            const io = std.Io.Threaded.global_single_threaded.io();
            std.Io.sleep(io, std.Io.Duration.fromSeconds(self.auth_manager.getPollInterval()), .awake) catch {};
        }

        // Handle profile selection if needed
        if (self.auth_manager.getState() == .awaiting_profile_selection) {
            if (self.auth_manager.getPendingProfiles()) |profiles| {
                std.debug.print("\nSelect a profile:\n", .{});
                for (profiles, 0..) |profile, i| {
                    std.debug.print("  [{d}] {s}\n", .{ i, profile.username });
                }
                std.debug.print("\nEnter number (0-{d}): ", .{profiles.len - 1});

                // Read selection from stdin
                var select_buf: [16]u8 = undefined;
                if (readStdinLine(&select_buf)) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t\r\n");
                    if (std.fmt.parseInt(usize, trimmed, 10)) |index| {
                        self.auth_manager.selectProfile(index) catch |err| {
                            std.debug.print("Failed to select profile: {}\n", .{err});
                            return;
                        };
                    } else |_| {
                        std.debug.print("Invalid selection\n", .{});
                        return;
                    }
                } else |_| {
                    std.debug.print("Input error\n", .{});
                    return;
                }
            }
        }

        if (self.auth_manager.isAuthenticated()) {
            std.debug.print("\n", .{});
            std.debug.print("Authentication successful!\n", .{});
            std.debug.print("Logged in as: {s}\n", .{self.credentials.username orelse "unknown"});
            std.debug.print("\n", .{});
        }
    }

    /// /auth logout command
    fn cmdAuthLogout(self: *Self) void {
        self.auth_manager.logout();

        // Clear credentials
        self.credentials.* = auth.ServerCredentials.empty();

        std.debug.print("Logged out. Credentials cleared.\n", .{});
    }

    /// /auth refresh command
    fn cmdAuthRefresh(self: *Self) void {
        if (self.credentials.refresh_token == null) {
            std.debug.print("No refresh token available. Use /auth login device first.\n", .{});
            return;
        }

        std.debug.print("Refreshing tokens...\n", .{});

        self.auth_manager.refreshCredentials() catch |err| {
            std.debug.print("Token refresh failed: {}\n", .{err});
            return;
        };

        std.debug.print("Tokens refreshed successfully.\n", .{});
    }

    /// /auth select <username> command
    fn cmdAuthSelect(self: *Self, username: []const u8) void {
        std.debug.print("Selecting profile: {s}...\n", .{username});

        self.auth_manager.selectProfileByUsername(username) catch |err| {
            std.debug.print("Failed to select profile: {}\n", .{err});
            return;
        };

        std.debug.print("Profile selected successfully.\n", .{});
        if (self.auth_manager.isAuthenticated()) {
            std.debug.print("Logged in as: {s}\n", .{self.credentials.username orelse "unknown"});
        }
    }

    /// /auth profiles command
    fn cmdAuthProfiles(self: *Self) void {
        if (self.credentials.access_token == null) {
            std.debug.print("No access token available. Use /auth login device first.\n", .{});
            return;
        }

        std.debug.print("Fetching profiles...\n", .{});

        const profiles = self.auth_manager.listProfiles() catch |err| {
            std.debug.print("Failed to fetch profiles: {}\n", .{err});
            return;
        };

        std.debug.print("\n", .{});
        std.debug.print("=== Available Profiles ===\n", .{});
        for (profiles, 0..) |profile, i| {
            std.debug.print("  [{d}] {s}\n", .{ i + 1, profile.username });
        }
        std.debug.print("\n", .{});
        std.debug.print("Use /auth select <username> to switch profiles.\n", .{});
    }

    /// /auth persistence command
    fn cmdAuthPersistence(self: *Self, storage_type: ?[]const u8) void {
        if (storage_type) |type_str| {
            // Set storage type
            if (std.ascii.eqlIgnoreCase(type_str, "memory")) {
                self.auth_manager.setStoreType(.memory) catch |err| {
                    std.debug.print("Failed to switch to memory storage: {}\n", .{err});
                    return;
                };
                std.debug.print("Switched to memory-only storage.\n", .{});
                std.debug.print("WARNING: Credentials will NOT persist across restarts.\n", .{});
            } else if (std.ascii.eqlIgnoreCase(type_str, "encrypted")) {
                self.auth_manager.setStoreType(.encrypted) catch |err| {
                    std.debug.print("Failed to switch to encrypted storage: {}\n", .{err});
                    return;
                };
                std.debug.print("Switched to encrypted persistent storage.\n", .{});
            } else {
                std.debug.print("Unknown storage type: {s}\n", .{type_str});
                std.debug.print("Available types: memory, encrypted\n", .{});
            }
        } else {
            // Show current storage type
            const current = self.auth_manager.getStoreType();
            std.debug.print("\n", .{});
            std.debug.print("=== Credential Storage ===\n", .{});
            std.debug.print("  Current: {s}\n", .{current.toString()});
            std.debug.print("\n", .{});
            std.debug.print("Available storage types:\n", .{});
            std.debug.print("  memory    - In-memory only (lost on restart)\n", .{});
            std.debug.print("  encrypted - Encrypted file storage (persists)\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("Use /auth persistence <type> to switch.\n", .{});
        }
    }

    /// /status command
    fn cmdStatus(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("=== Server Status ===\n", .{});
        std.debug.print("  Running: yes\n", .{});
        std.debug.print("  Authenticated: {s}\n", .{if (self.auth_manager.isAuthenticated()) "yes" else "no"});
        if (self.credentials.username) |name| {
            std.debug.print("  Username: {s}\n", .{name});
        }
        std.debug.print("\n", .{});
    }

    /// /quit command
    fn cmdQuit(self: *Self) void {
        _ = self;
        std.debug.print("Stopping server...\n", .{});
        // Signal shutdown - this would need to be connected to main server loop
        std.process.exit(0);
    }
};

test "console init" {
    const allocator = std.testing.allocator;

    var creds = auth.ServerCredentials.empty();
    var auth_manager = auth.AuthManager.init(allocator, "test", &creds);
    defer auth_manager.deinit();

    var console = Console.init(allocator, &auth_manager, &creds);
    defer console.deinit();

    try std.testing.expect(!console.running.load(.acquire));
}
