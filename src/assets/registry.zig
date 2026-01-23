/// AssetRegistry - Central coordinator for all game assets
///
/// Manages loading assets from Assets.zip and generating Update* packets
/// to send to clients during the loading phase.

const std = @import("std");
const common = @import("types/common.zig");
const IndexedAssetMap = @import("indexed_map.zig").IndexedAssetMap;
const packet = @import("packet.zig");
const store = @import("store.zig");

const log = std.log.scoped(.asset_registry);

const UpdateType = common.UpdateType;
const AssetType = common.AssetType;

/// AssetRegistry holds all loaded assets and generates packets
pub const AssetRegistry = struct {
    allocator: std.mem.Allocator,

    /// Asset store for reading from ZIP
    asset_store: ?store.AssetStore,

    /// Audio categories
    audio_categories: IndexedAssetMap(packet.AudioCategoryAsset),

    /// Environments
    environments: IndexedAssetMap(packet.EnvironmentAsset),

    /// Whether assets have been loaded
    loaded: bool,

    /// Statistics
    total_assets: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .asset_store = null,
            .audio_categories = IndexedAssetMap(packet.AudioCategoryAsset).init(allocator),
            .environments = IndexedAssetMap(packet.EnvironmentAsset).init(allocator),
            .loaded = false,
            .total_assets = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.asset_store) |*s| {
            s.deinit();
        }
        self.audio_categories.deinit();
        self.environments.deinit();
    }

    /// Load assets from a ZIP file
    pub fn loadFromZip(self: *Self, zip_path: []const u8) !void {
        log.info("Loading assets from: {s}", .{zip_path});

        // Initialize asset store
        self.asset_store = try store.AssetStore.init(self.allocator, zip_path);
        errdefer {
            if (self.asset_store) |*s| s.deinit();
            self.asset_store = null;
        }

        try self.asset_store.?.load();

        log.info("Asset store indexed {d} files", .{self.asset_store.?.count()});

        // Load individual asset types
        // For now, we'll create placeholder entries - actual JSON parsing comes in later phases
        try self.loadPlaceholderAssets();

        self.loaded = true;
        log.info("Asset registry loaded: {d} total assets", .{self.total_assets});
    }

    /// Load placeholder assets (used until JSON parsing is implemented)
    pub fn loadPlaceholderAssets(self: *Self) !void {
        // Add some placeholder audio categories
        // These match common Hytale audio categories
        _ = try self.audio_categories.put("sfx", .{ .id = "sfx", .volume = 1.0 });
        _ = try self.audio_categories.put("music", .{ .id = "music", .volume = 0.8 });
        _ = try self.audio_categories.put("ambient", .{ .id = "ambient", .volume = 1.0 });
        _ = try self.audio_categories.put("ui", .{ .id = "ui", .volume = 1.0 });
        self.total_assets += 4;

        // Add a default environment
        _ = try self.environments.put("default", .{
            .id = "default",
            .water_tint = common.Color.fromHex("#4A90D9"),
        });
        self.total_assets += 1;

        log.debug("Loaded {d} placeholder assets", .{self.total_assets});
    }

    /// Generate all Update* packets for initial client load
    /// Returns a list of (packet_id, payload) tuples
    pub fn generateInitPackets(self: *Self) !std.ArrayList(GeneratedPacket) {
        var packets: std.ArrayList(GeneratedPacket) = .empty;
        errdefer {
            for (packets.items) |p| {
                self.allocator.free(p.payload);
            }
            packets.deinit(self.allocator);
        }

        // Generate packets for all asset types
        // Order matters for some assets (dependencies)

        // Simple assets first
        try self.generateAudioCategoriesPacket(&packets);
        try self.generateEnvironmentsPacket(&packets);

        // Generate empty packets for all other required asset types
        try self.generateEmptyPackets(&packets);

        return packets;
    }

    fn generateAudioCategoriesPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = packet.AssetSerializer(packet.AudioCategoryAsset);

        // Collect entries
        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.audio_categories.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{ .index = entry.index, .value = entry.value });
        }

        const payload = try S.serialize(
            self.allocator,
            .init,
            @intCast(self.audio_categories.maxId()),
            entries.items,
            &[_]u8{},
            packet.serializeAudioCategory,
        );

        try packets.append(self.allocator, .{
            .packet_id = AssetType.audio_categories.getPacketId(),
            .payload = payload,
        });

        log.debug("Generated UpdateAudioCategories: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateEnvironmentsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = packet.AssetSerializer(packet.EnvironmentAsset);

        // Collect entries
        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.environments.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{ .index = entry.index, .value = entry.value });
        }

        // Environments have an extra byte: rebuildMapGeometry (bool)
        const extra_bytes = [_]u8{0}; // rebuildMapGeometry = false

        const payload = try S.serialize(
            self.allocator,
            .init,
            @intCast(self.environments.maxId()),
            entries.items,
            &extra_bytes,
            packet.serializeEnvironment,
        );

        try packets.append(self.allocator, .{
            .packet_id = AssetType.environments.getPacketId(),
            .payload = payload,
        });

        log.debug("Generated UpdateEnvironments: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    /// Generate empty packets for all required asset types
    fn generateEmptyPackets(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        // All asset types that need Update* packets
        const all_types = [_]AssetType{
            .block_types,
            .block_hitboxes,
            .block_sound_sets,
            .item_sound_sets,
            .block_particle_sets,
            .block_breaking_decals,
            .block_sets,
            .weathers,
            .trails,
            .particle_systems,
            .particle_spawners,
            .entity_effects,
            .item_player_animations,
            .model_vfxs,
            .items,
            .item_qualities,
            .item_categories,
            .item_reticles,
            .fieldcraft_categories,
            .resource_types,
            .recipes,
            // .environments - already generated above
            .ambience_fx,
            .fluid_fx,
            .translations,
            .sound_events,
            .interactions,
            .root_interactions,
            .unarmed_interactions,
            .entity_stat_types,
            .entity_ui_components,
            .hitbox_collision_config,
            .repulsion_config,
            .view_bobbing,
            .camera_shake,
            .block_groups,
            .sound_sets,
            // .audio_categories - already generated above
            .reverb_effects,
            .equalizer_effects,
            .fluids,
            .tag_patterns,
            .projectile_configs,
        };

        for (all_types) |asset_type| {
            const payload = try packet.buildEmptyUpdatePacket(self.allocator, asset_type);
            try packets.append(self.allocator, .{
                .packet_id = asset_type.getPacketId(),
                .payload = payload,
            });
        }

        log.debug("Generated {d} empty asset packets", .{all_types.len});
    }

    /// Check if assets are loaded
    pub fn isLoaded(self: *const Self) bool {
        return self.loaded;
    }

    /// Get total asset count
    pub fn count(self: *const Self) usize {
        return self.total_assets;
    }
};

/// A generated packet ready to send
pub const GeneratedPacket = struct {
    packet_id: u32,
    payload: []u8,
};

test "AssetRegistry init and deinit" {
    const allocator = std.testing.allocator;

    var registry = AssetRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expect(!registry.isLoaded());
}

test "AssetRegistry placeholder loading" {
    const allocator = std.testing.allocator;

    var registry = AssetRegistry.init(allocator);
    defer registry.deinit();

    // Load placeholders (without ZIP)
    try registry.loadPlaceholderAssets();

    try std.testing.expect(registry.audio_categories.count() > 0);
    try std.testing.expect(registry.environments.count() > 0);
}

test "AssetRegistry generate packets" {
    const allocator = std.testing.allocator;

    var registry = AssetRegistry.init(allocator);
    defer registry.deinit();

    try registry.loadPlaceholderAssets();

    var packets = try registry.generateInitPackets();
    defer {
        for (packets.items) |p| {
            allocator.free(p.payload);
        }
        packets.deinit(allocator);
    }

    // Should have generated packets for all asset types
    try std.testing.expect(packets.items.len > 30);

    // Check that audio categories packet exists
    var found_audio = false;
    for (packets.items) |p| {
        if (p.packet_id == 80) {
            found_audio = true;
            break;
        }
    }
    try std.testing.expect(found_audio);
}
