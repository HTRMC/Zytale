const std = @import("std");

/// Hytale packet frame format:
/// [4 bytes] Length (u32 LE) - size of payload only
/// [4 bytes] Packet ID (u32 LE)
/// [N bytes] Payload (possibly Zstd compressed)
pub const FRAME_HEADER_SIZE: usize = 8;
pub const MAX_PAYLOAD_SIZE: usize = 1_677_721_600; // ~1.6 GB from Java source

pub const Frame = struct {
    id: u32,
    payload: []const u8,
    /// If true, payload memory is owned and must be freed with deinit()
    owned: bool = false,
    allocator: ?std.mem.Allocator = null,

    /// Free owned payload memory
    pub fn deinit(self: *Frame) void {
        if (self.owned) {
            if (self.allocator) |alloc| {
                alloc.free(self.payload);
            }
        }
        self.payload = &[_]u8{};
        self.owned = false;
    }
};

pub const FrameParser = struct {
    buffer: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FrameParser {
        return .{
            .buffer = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FrameParser) void {
        self.buffer.deinit(self.allocator);
    }

    /// Feed raw bytes into the parser
    pub fn feed(self: *FrameParser, data: []const u8) void {
        self.buffer.appendSlice(self.allocator, data) catch {};
    }

    /// Try to extract the next complete frame
    /// Note: The returned Frame owns its payload memory and must be freed with frame.deinit()
    pub fn nextFrame(self: *FrameParser) ?Frame {
        if (self.buffer.items.len < FRAME_HEADER_SIZE) {
            return null;
        }

        // Read header (little-endian)
        const length = std.mem.readInt(u32, self.buffer.items[0..4], .little);
        const packet_id = std.mem.readInt(u32, self.buffer.items[4..8], .little);

        // Validate length
        if (length > MAX_PAYLOAD_SIZE) {
            // Invalid frame - clear buffer and return null
            self.buffer.clearRetainingCapacity();
            return null;
        }

        const total_size = FRAME_HEADER_SIZE + length;
        if (self.buffer.items.len < total_size) {
            // Not enough data yet
            return null;
        }

        // Copy payload to owned memory BEFORE modifying buffer
        // This prevents the dangling pointer bug where the slice would point to
        // buffer memory that gets corrupted when we remove the consumed bytes
        const payload = self.allocator.alloc(u8, length) catch return null;
        @memcpy(payload, self.buffer.items[FRAME_HEADER_SIZE..total_size]);

        // Remove consumed bytes from buffer
        const remaining = self.buffer.items[total_size..];
        std.mem.copyForwards(u8, self.buffer.items[0..remaining.len], remaining);
        self.buffer.shrinkRetainingCapacity(remaining.len);

        return Frame{
            .id = packet_id,
            .payload = payload,
            .owned = true,
            .allocator = self.allocator,
        };
    }

    /// Reset the parser state
    pub fn reset(self: *FrameParser) void {
        self.buffer.clearRetainingCapacity();
    }
};

/// Encode a frame with the given packet ID and payload
pub fn encodeFrame(allocator: std.mem.Allocator, packet_id: u32, payload: []const u8) ![]u8 {
    const total_size = FRAME_HEADER_SIZE + payload.len;
    const buf = try allocator.alloc(u8, total_size);

    // Write length (payload size only, not including header)
    std.mem.writeInt(u32, buf[0..4], @intCast(payload.len), .little);

    // Write packet ID
    std.mem.writeInt(u32, buf[4..8], packet_id, .little);

    // Write payload
    @memcpy(buf[FRAME_HEADER_SIZE..], payload);

    return buf;
}

test "frame parsing" {
    const allocator = std.testing.allocator;

    var parser = FrameParser.init(allocator);
    defer parser.deinit();

    // Create a test frame: ID=42, payload="hello"
    var test_frame: [13]u8 = undefined;
    std.mem.writeInt(u32, test_frame[0..4], 5, .little); // length = 5
    std.mem.writeInt(u32, test_frame[4..8], 42, .little); // id = 42
    @memcpy(test_frame[8..13], "hello");

    // Feed partial data
    parser.feed(test_frame[0..4]);
    try std.testing.expect(parser.nextFrame() == null);

    // Feed rest
    parser.feed(test_frame[4..]);

    var frame_result = parser.nextFrame();
    try std.testing.expect(frame_result != null);
    defer frame_result.?.deinit(); // Free owned payload memory
    try std.testing.expectEqual(@as(u32, 42), frame_result.?.id);
    try std.testing.expectEqualStrings("hello", frame_result.?.payload);
    try std.testing.expect(frame_result.?.owned); // Verify ownership flag is set
}

test "encode frame" {
    const allocator = std.testing.allocator;

    const encoded = try encodeFrame(allocator, 123, "test");
    defer allocator.free(encoded);

    try std.testing.expectEqual(@as(usize, 12), encoded.len);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, encoded[0..4], .little));
    try std.testing.expectEqual(@as(u32, 123), std.mem.readInt(u32, encoded[4..8], .little));
    try std.testing.expectEqualStrings("test", encoded[8..12]);
}
