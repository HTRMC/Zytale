const std = @import("std");
const Connection = @import("connection.zig").Connection;
const registry = @import("protocol");
const world_packets = @import("../protocol/packets/world.zig");
const player_packets = @import("../protocol/packets/player.zig");
const entity_packets = @import("../protocol/packets/entity.zig");
const World = @import("../world/world.zig").World;
const Chunk = @import("../world/chunk.zig").Chunk;
const constants = @import("../world/constants.zig");

const log = std.log.scoped(.join);

/// Player join sequence handler
/// Manages the packet sequence for joining a world
pub const JoinSequence = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    world: *World,

    /// View radius in chunks
    view_radius: u32,

    /// Current stage of the join sequence
    stage: JoinStage,

    /// Chunks sent so far
    chunks_sent: usize,
    total_chunks: usize,

    pub const JoinStage = enum {
        not_started,
        sending_initial_packets,
        sending_chunks,
        spawning_player,
        waiting_for_ready,
        complete,
        failed,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, connection: *Connection, world: *World, view_radius: u32) Self {
        const diameter = view_radius * 2 + 1;
        const total_chunks = diameter * diameter;

        return .{
            .allocator = allocator,
            .connection = connection,
            .world = world,
            .view_radius = view_radius,
            .stage = .not_started,
            .chunks_sent = 0,
            .total_chunks = total_chunks,
        };
    }

    /// Execute the join sequence
    /// This sends all the packets needed to join a world
    pub fn execute(self: *Self) !void {
        log.info("Starting join sequence for client {d}", .{self.connection.client_id});

        self.stage = .sending_initial_packets;

        // Step 1: Send initial setup packets
        try self.sendInitialPackets();

        self.stage = .sending_chunks;

        // Step 2: Send chunks around spawn
        try self.sendChunks();

        self.stage = .spawning_player;

        // Step 3: Spawn player entity
        try self.spawnPlayer();

        self.stage = .waiting_for_ready;

        log.info("Join sequence complete, waiting for ClientReady", .{});
    }

    /// Send initial setup packets
    fn sendInitialPackets(self: *Self) !void {
        // ConnectAccept (ID=14)
        {
            const packet = player_packets.ConnectAccept.success();
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            try self.connection.sendPacket(registry.ConnectAccept.id, data);
            log.debug("Sent ConnectAccept", .{});
        }

        // SetClientId (ID=100)
        {
            const packet = player_packets.SetClientId{ .client_id = self.connection.client_id };
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            try self.connection.sendPacket(registry.SetClientId.id, data);
            log.debug("Sent SetClientId: {d}", .{self.connection.client_id});
        }

        // ViewRadius (ID=32)
        {
            const packet = player_packets.ViewRadius{ .radius = self.view_radius };
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            try self.connection.sendPacket(registry.ViewRadius.id, data);
            log.debug("Sent ViewRadius: {d}", .{self.view_radius});
        }

        // JoinWorld (ID=104)
        {
            const packet = world_packets.JoinWorld{
                .clear_world = true,
                .fade_in_out = false,
                .world_uuid = self.world.uuid,
            };
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            try self.connection.sendPacket(registry.JoinWorld.id, data);
            log.debug("Sent JoinWorld", .{});
        }

        // SetGameMode (ID=101) - Creative mode
        {
            const packet = player_packets.SetGameMode{ .mode = .creative };
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            try self.connection.sendPacket(registry.SetGameMode.id, data);
            log.debug("Sent SetGameMode: creative", .{});
        }

        // SetEntitySeed (ID=160)
        {
            var rng = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));
            const seed = rng.random().int(u32);
            const packet = player_packets.SetEntitySeed{ .seed = seed };
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            try self.connection.sendPacket(registry.SetEntitySeed.id, data);
            log.debug("Sent SetEntitySeed: {d}", .{seed});
        }
    }

    /// Send all chunks within view radius
    fn sendChunks(self: *Self) !void {
        const spawn = self.world.getSpawnPoint();
        const center = constants.worldToChunk(spawn.x, spawn.z);

        const r: i32 = @intCast(self.view_radius);
        var cz: i32 = center.cz - r;

        while (cz <= center.cz + r) : (cz += 1) {
            var cx: i32 = center.cx - r;

            while (cx <= center.cx + r) : (cx += 1) {
                try self.sendChunk(cx, cz);
                self.chunks_sent += 1;

                if (self.chunks_sent % 10 == 0) {
                    log.debug("Sent {d}/{d} chunks", .{ self.chunks_sent, self.total_chunks });
                }
            }
        }

        log.info("Sent {d} chunks", .{self.chunks_sent});
    }

    /// Send a single chunk to the client
    fn sendChunk(self: *Self, cx: i32, cz: i32) !void {
        const chunk = try self.world.getChunk(cx, cz);

        // Send heightmap (ID=132)
        {
            const packet = try world_packets.SetChunkHeightmap.fromChunk(self.allocator, chunk);
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            if (packet.heightmap) |hm| {
                self.allocator.free(hm);
            }
            try self.connection.sendPacket(registry.SetChunkHeightmap.id, data);
        }

        // Send tintmap (ID=133)
        {
            const packet = try world_packets.SetChunkTintmap.fromChunk(self.allocator, chunk);
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            if (packet.tintmap) |tm| {
                self.allocator.free(tm);
            }
            try self.connection.sendPacket(registry.SetChunkTintmap.id, data);
        }

        // Send environments (ID=134)
        {
            const packet = try world_packets.SetChunkEnvironments.fromChunk(self.allocator, chunk);
            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);
            if (packet.environments) |env| {
                self.allocator.free(env);
            }
            try self.connection.sendPacket(registry.SetChunkEnvironments.id, data);
        }

        // Send each section (ID=131)
        for (0..constants.HEIGHT_SECTIONS) |section_idx| {
            const section = chunk.getSection(@intCast(section_idx));

            // Serialize section data
            const section_data = try section.serialize(self.allocator);
            defer self.allocator.free(section_data);

            const packet = world_packets.SetChunk{
                .chunk_x = cx,
                .section_y = @intCast(section_idx),
                .chunk_z = cz,
                .section_data = section_data,
                .local_light = null,
                .global_light = null,
            };

            const data = try packet.serialize(self.allocator);
            defer self.allocator.free(data);

            try self.connection.sendPacket(registry.SetChunk.id, data);
        }
    }

    /// Spawn the player entity at spawn point
    fn spawnPlayer(self: *Self) !void {
        const spawn = self.world.getSpawnPoint();

        // EntityUpdates (ID=161) with player spawn
        var updates = try entity_packets.EntityUpdates.spawnPlayer(
            self.allocator,
            self.connection.client_id,
            @floatFromInt(spawn.x),
            @floatFromInt(spawn.y),
            @floatFromInt(spawn.z),
        );
        defer updates.deinit();

        const data = try updates.serialize(self.allocator);
        defer self.allocator.free(data);

        try self.connection.sendPacket(registry.EntityUpdates.id, data);

        log.info("Spawned player at ({d}, {d}, {d})", .{ spawn.x, spawn.y, spawn.z });
    }

    /// Handle ClientReady packet (ID=105)
    pub fn onClientReady(self: *Self) void {
        if (self.stage == .waiting_for_ready) {
            self.stage = .complete;
            log.info("Client {d} is ready to play!", .{self.connection.client_id});
        }
    }

    /// Check if join sequence is complete
    pub fn isComplete(self: *const Self) bool {
        return self.stage == .complete;
    }

    /// Get current stage
    pub fn getStage(self: *const Self) JoinStage {
        return self.stage;
    }

    /// Get progress percentage
    pub fn progress(self: *const Self) f32 {
        return switch (self.stage) {
            .not_started => 0.0,
            .sending_initial_packets => 10.0,
            .sending_chunks => 10.0 + (@as(f32, @floatFromInt(self.chunks_sent)) / @as(f32, @floatFromInt(self.total_chunks))) * 80.0,
            .spawning_player => 95.0,
            .waiting_for_ready => 98.0,
            .complete => 100.0,
            .failed => 0.0,
        };
    }
};

/// Simplified join handler that just sends essential packets
/// Use this for testing when full sequence isn't needed
pub fn sendMinimalJoinPackets(
    allocator: std.mem.Allocator,
    connection: *Connection,
    world_uuid: [16]u8,
) !void {
    // ConnectAccept
    {
        var data: [1]u8 = .{0};
        try connection.sendPacket(registry.ConnectAccept.id, &data);
    }

    // SetClientId
    {
        var data: [4]u8 = undefined;
        std.mem.writeInt(u32, &data, connection.client_id, .little);
        try connection.sendPacket(registry.SetClientId.id, &data);
    }

    // ViewRadius
    {
        var data: [4]u8 = undefined;
        std.mem.writeInt(u32, &data, 6, .little);
        try connection.sendPacket(registry.ViewRadius.id, &data);
    }

    // JoinWorld
    {
        var data: [18]u8 = undefined;
        data[0] = 1; // clearWorld
        data[1] = 0; // fadeInOut
        @memcpy(data[2..18], &world_uuid);
        try connection.sendPacket(registry.JoinWorld.id, &data);
    }

    // SetGameMode (creative)
    {
        var data: [1]u8 = .{1};
        try connection.sendPacket(registry.SetGameMode.id, &data);
    }

    // SetEntitySeed
    {
        var data: [4]u8 = undefined;
        var rng = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));
        std.mem.writeInt(u32, &data, rng.random().int(u32), .little);
        try connection.sendPacket(registry.SetEntitySeed.id, &data);
    }

    _ = allocator;
    log.info("Sent minimal join packets", .{});
}

test "join stage progression" {
    const std_testing = std.testing;

    // Just test the enum values
    try std_testing.expectEqual(JoinSequence.JoinStage.not_started, JoinSequence.JoinStage.not_started);
    try std_testing.expect(@intFromEnum(JoinSequence.JoinStage.complete) > @intFromEnum(JoinSequence.JoinStage.not_started));
}
