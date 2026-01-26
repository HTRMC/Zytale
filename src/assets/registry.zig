/// AssetRegistry - Central coordinator for all game assets
///
/// Manages loading assets from Assets.zip and generating Update* packets
/// to send to clients during the loading phase.

const std = @import("std");
const common = @import("types/common.zig");
const IndexedAssetMap = @import("indexed_map.zig").IndexedAssetMap;
const store = @import("store.zig");
const json = @import("json.zig");

// Asset packet imports from protocol/packets/assets/
const asset_packets = @import("../protocol/packets/assets/mod.zig");
const serializer = asset_packets.serializer;

// Asset type imports
const audio_category = @import("types/audio_category.zig");
const reverb_effect = @import("types/reverb_effect.zig");
const equalizer_effect = @import("types/equalizer_effect.zig");
const tag_pattern = @import("types/tag_pattern.zig");
const trail = @import("types/trail.zig");
const entity_effect = @import("types/entity_effect.zig");
const block_type = @import("types/block_type.zig");

const log = std.log.scoped(.asset_registry);

const UpdateType = common.UpdateType;
const AssetType = common.AssetType;

/// Simple struct for packet serialization (id + volume)
const AudioCategoryEntry = struct {
    id: []const u8,
    volume: f32,
};

/// AssetRegistry holds all loaded assets and generates packets
pub const AssetRegistry = struct {
    allocator: std.mem.Allocator,

    /// Asset store for reading from ZIP
    asset_store: ?store.AssetStore,

    /// Audio categories
    audio_categories: IndexedAssetMap(audio_category.AudioCategoryAsset),

    /// Reverb effects
    reverb_effects: IndexedAssetMap(reverb_effect.ReverbEffectAsset),

    /// Equalizer effects
    equalizer_effects: IndexedAssetMap(equalizer_effect.EqualizerEffectAsset),

    /// Tag patterns
    tag_patterns: IndexedAssetMap(tag_pattern.TagPatternAsset),

    /// Trails
    trails: IndexedAssetMap(trail.TrailAsset),

    /// Environments
    environments: IndexedAssetMap(asset_packets.UpdateEnvironments.EnvironmentAsset),

    /// Entity effects
    entity_effects: IndexedAssetMap(entity_effect.EntityEffectAsset),

    /// Whether assets have been loaded
    loaded: bool,

    /// Statistics
    total_assets: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .asset_store = null,
            .audio_categories = IndexedAssetMap(audio_category.AudioCategoryAsset).init(allocator),
            .reverb_effects = IndexedAssetMap(reverb_effect.ReverbEffectAsset).init(allocator),
            .equalizer_effects = IndexedAssetMap(equalizer_effect.EqualizerEffectAsset).init(allocator),
            .tag_patterns = IndexedAssetMap(tag_pattern.TagPatternAsset).init(allocator),
            .trails = IndexedAssetMap(trail.TrailAsset).init(allocator),
            .environments = IndexedAssetMap(asset_packets.UpdateEnvironments.EnvironmentAsset).init(allocator),
            .entity_effects = IndexedAssetMap(entity_effect.EntityEffectAsset).init(allocator),
            .loaded = false,
            .total_assets = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.asset_store) |*s| {
            s.deinit();
        }

        // Deinit asset maps that hold allocated data
        var audio_iter = self.audio_categories.iterator();
        while (audio_iter.next()) |entry| {
            var asset = entry.value.*;
            asset.deinit(self.allocator);
        }
        self.audio_categories.deinit();

        var reverb_iter = self.reverb_effects.iterator();
        while (reverb_iter.next()) |entry| {
            var asset = entry.value.*;
            asset.deinit(self.allocator);
        }
        self.reverb_effects.deinit();

        var eq_iter = self.equalizer_effects.iterator();
        while (eq_iter.next()) |entry| {
            var asset = entry.value.*;
            asset.deinit(self.allocator);
        }
        self.equalizer_effects.deinit();

        var tag_iter = self.tag_patterns.iterator();
        while (tag_iter.next()) |entry| {
            var asset = entry.value.*;
            asset.deinit(self.allocator);
        }
        self.tag_patterns.deinit();

        var trail_iter = self.trails.iterator();
        while (trail_iter.next()) |entry| {
            var asset = entry.value.*;
            asset.deinit(self.allocator);
        }
        self.trails.deinit();

        var effect_iter = self.entity_effects.iterator();
        while (effect_iter.next()) |entry| {
            var asset = entry.value.*;
            asset.deinit(self.allocator);
        }
        self.entity_effects.deinit();

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

        // Load individual asset types from ZIP
        try self.loadAudioCategoriesFromZip();
        try self.loadReverbEffectsFromZip();
        try self.loadEqualizerEffectsFromZip();
        try self.loadTagPatternsFromZip();
        try self.loadTrailsFromZip();
        try self.loadEntityEffectsFromZip();

        // Load placeholder for environments (JSON parsing not implemented yet)
        try self.loadPlaceholderEnvironments();

        self.loaded = true;
        log.info("Asset registry loaded: {d} total assets", .{self.total_assets});
    }

    /// Load AudioCategories from ZIP
    fn loadAudioCategoriesFromZip(self: *Self) !void {
        const asset_store_ptr = &self.asset_store.?;
        const prefix = common.getZipPath(.audio_categories);

        var iter = asset_store_ptr.iterateDirectory(prefix);
        var loaded: usize = 0;

        while (iter.next()) |info| {
            // Only process .json files
            if (!std.mem.endsWith(u8, info.path, ".json")) continue;

            // Read file content
            const content = asset_store_ptr.readAsset(info.path) catch |err| {
                log.warn("Failed to read {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(content);

            // Extract asset ID from filename
            const asset_id = json.extractAssetId(self.allocator, info.path) catch |err| {
                log.warn("Failed to extract ID from {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(asset_id);

            // Parse JSON
            const asset = audio_category.AudioCategoryAsset.parseJson(self.allocator, asset_id, content) catch |err| {
                log.warn("Failed to parse {s}: {}", .{ info.path, err });
                continue;
            };

            _ = self.audio_categories.put(asset.id, asset) catch |err| {
                log.warn("Failed to store {s}: {}", .{ asset_id, err });
                var mutable_asset = asset;
                mutable_asset.deinit(self.allocator);
                continue;
            };

            loaded += 1;
        }

        self.total_assets += loaded;
        log.info("Loaded {d} AudioCategories", .{loaded});
    }

    /// Load ReverbEffects from ZIP
    fn loadReverbEffectsFromZip(self: *Self) !void {
        const asset_store_ptr = &self.asset_store.?;
        const prefix = common.getZipPath(.reverb_effects);

        var iter = asset_store_ptr.iterateDirectory(prefix);
        var loaded: usize = 0;

        while (iter.next()) |info| {
            if (!std.mem.endsWith(u8, info.path, ".json")) continue;

            const content = asset_store_ptr.readAsset(info.path) catch |err| {
                log.warn("Failed to read {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(content);

            const asset_id = json.extractAssetId(self.allocator, info.path) catch |err| {
                log.warn("Failed to extract ID from {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(asset_id);

            const asset = reverb_effect.ReverbEffectAsset.parseJson(self.allocator, asset_id, content) catch |err| {
                log.warn("Failed to parse {s}: {}", .{ info.path, err });
                continue;
            };

            _ = self.reverb_effects.put(asset.id, asset) catch |err| {
                log.warn("Failed to store {s}: {}", .{ asset_id, err });
                var mutable_asset = asset;
                mutable_asset.deinit(self.allocator);
                continue;
            };

            loaded += 1;
        }

        self.total_assets += loaded;
        log.info("Loaded {d} ReverbEffects", .{loaded});
    }

    /// Load EqualizerEffects from ZIP
    fn loadEqualizerEffectsFromZip(self: *Self) !void {
        const asset_store_ptr = &self.asset_store.?;
        const prefix = common.getZipPath(.equalizer_effects);

        var iter = asset_store_ptr.iterateDirectory(prefix);
        var loaded: usize = 0;

        while (iter.next()) |info| {
            if (!std.mem.endsWith(u8, info.path, ".json")) continue;

            const content = asset_store_ptr.readAsset(info.path) catch |err| {
                log.warn("Failed to read {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(content);

            const asset_id = json.extractAssetId(self.allocator, info.path) catch |err| {
                log.warn("Failed to extract ID from {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(asset_id);

            const asset = equalizer_effect.EqualizerEffectAsset.parseJson(self.allocator, asset_id, content) catch |err| {
                log.warn("Failed to parse {s}: {}", .{ info.path, err });
                continue;
            };

            _ = self.equalizer_effects.put(asset.id, asset) catch |err| {
                log.warn("Failed to store {s}: {}", .{ asset_id, err });
                var mutable_asset = asset;
                mutable_asset.deinit(self.allocator);
                continue;
            };

            loaded += 1;
        }

        self.total_assets += loaded;
        log.info("Loaded {d} EqualizerEffects", .{loaded});
    }

    /// Load TagPatterns from ZIP
    fn loadTagPatternsFromZip(self: *Self) !void {
        const asset_store_ptr = &self.asset_store.?;
        const prefix = common.getZipPath(.tag_patterns);

        var iter = asset_store_ptr.iterateDirectory(prefix);
        var loaded: usize = 0;

        while (iter.next()) |info| {
            if (!std.mem.endsWith(u8, info.path, ".json")) continue;

            const content = asset_store_ptr.readAsset(info.path) catch |err| {
                log.warn("Failed to read {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(content);

            const asset_id = json.extractAssetId(self.allocator, info.path) catch |err| {
                log.warn("Failed to extract ID from {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(asset_id);

            const asset = tag_pattern.TagPatternAsset.parseJson(self.allocator, asset_id, content) catch |err| {
                log.warn("Failed to parse {s}: {}", .{ info.path, err });
                continue;
            };

            _ = self.tag_patterns.put(asset.id, asset) catch |err| {
                log.warn("Failed to store {s}: {}", .{ asset_id, err });
                var mutable_asset = asset;
                mutable_asset.deinit(self.allocator);
                continue;
            };

            loaded += 1;
        }

        self.total_assets += loaded;
        log.info("Loaded {d} TagPatterns", .{loaded});
    }

    /// Load Trails from ZIP
    fn loadTrailsFromZip(self: *Self) !void {
        const asset_store_ptr = &self.asset_store.?;
        const prefix = common.getZipPath(.trails);

        var iter = asset_store_ptr.iterateDirectory(prefix);
        var loaded: usize = 0;

        while (iter.next()) |info| {
            if (!std.mem.endsWith(u8, info.path, ".json")) continue;

            const content = asset_store_ptr.readAsset(info.path) catch |err| {
                log.warn("Failed to read {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(content);

            const asset_id = json.extractAssetId(self.allocator, info.path) catch |err| {
                log.warn("Failed to extract ID from {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(asset_id);

            const asset = trail.TrailAsset.parseJson(self.allocator, asset_id, content) catch |err| {
                log.warn("Failed to parse {s}: {}", .{ info.path, err });
                continue;
            };

            _ = self.trails.put(asset.id, asset) catch |err| {
                log.warn("Failed to store {s}: {}", .{ asset_id, err });
                var mutable_asset = asset;
                mutable_asset.deinit(self.allocator);
                continue;
            };

            loaded += 1;
        }

        self.total_assets += loaded;
        log.info("Loaded {d} Trails", .{loaded});
    }

    /// Load EntityEffects from ZIP
    fn loadEntityEffectsFromZip(self: *Self) !void {
        const asset_store_ptr = &self.asset_store.?;
        const prefix = common.getZipPath(.entity_effects);

        var iter = asset_store_ptr.iterateDirectory(prefix);
        var loaded: usize = 0;

        while (iter.next()) |info| {
            if (!std.mem.endsWith(u8, info.path, ".json")) continue;

            const content = asset_store_ptr.readAsset(info.path) catch |err| {
                log.warn("Failed to read {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(content);

            const asset_id = json.extractAssetId(self.allocator, info.path) catch |err| {
                log.warn("Failed to extract ID from {s}: {}", .{ info.path, err });
                continue;
            };
            defer self.allocator.free(asset_id);

            const asset = entity_effect.EntityEffectAsset.parseJson(self.allocator, asset_id, content) catch |err| {
                log.warn("Failed to parse {s}: {}", .{ info.path, err });
                continue;
            };

            _ = self.entity_effects.put(asset.id, asset) catch |err| {
                log.warn("Failed to store {s}: {}", .{ asset_id, err });
                var mutable_asset = asset;
                mutable_asset.deinit(self.allocator);
                continue;
            };

            loaded += 1;
        }

        self.total_assets += loaded;
        log.info("Loaded {d} EntityEffects", .{loaded});
    }

    /// Load placeholder environments
    fn loadPlaceholderEnvironments(self: *Self) !void {
        _ = try self.environments.put("default", .{
            .id = "default",
            .water_tint = common.Color.fromHex("#4A90D9"),
        });
        self.total_assets += 1;
    }

    /// Load placeholder assets (fallback when ZIP is unavailable)
    pub fn loadPlaceholderAssets(self: *Self) !void {
        // Add placeholder audio categories
        const categories = [_]struct { id: []const u8, volume: f32 }{
            .{ .id = "sfx", .volume = 1.0 },
            .{ .id = "music", .volume = 0.8 },
            .{ .id = "ambient", .volume = 1.0 },
            .{ .id = "ui", .volume = 1.0 },
        };

        for (categories) |cat| {
            _ = try self.audio_categories.put(cat.id, audio_category.AudioCategoryAsset{
                .id = try self.allocator.dupe(u8, cat.id),
                .volume = cat.volume,
                .parent = null,
            });
            self.total_assets += 1;
        }

        // Add placeholder environment
        try self.loadPlaceholderEnvironments();

        log.info("Loaded {d} placeholder assets", .{self.total_assets});
    }

    /// Generate all Update* packets for initial client load
    pub fn generateInitPackets(self: *Self) !std.ArrayList(GeneratedPacket) {
        var packets: std.ArrayList(GeneratedPacket) = .empty;
        errdefer {
            for (packets.items) |p| {
                self.allocator.free(p.payload);
            }
            packets.deinit(self.allocator);
        }

        // Generate packets for implemented asset types
        try self.generateBlockTypesPacket(&packets);
        try self.generateAudioCategoriesPacket(&packets);
        try self.generateReverbEffectsPacket(&packets);
        try self.generateEqualizerEffectsPacket(&packets);
        try self.generateTagPatternsPacket(&packets);
        try self.generateTrailsPacket(&packets);
        try self.generateEnvironmentsPacket(&packets);
        try self.generateEntityEffectsPacket(&packets);

        // Generate empty packets for all other required asset types
        try self.generateEmptyPackets(&packets);

        return packets;
    }

    fn generateAudioCategoriesPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = serializer.AssetSerializer(asset_packets.UpdateAudioCategories.AudioCategoryEntry);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.audio_categories.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = .{ .id = entry.value.id, .volume = entry.value.volume },
            });
        }

        const payload = try asset_packets.UpdateAudioCategories.serialize(
            self.allocator,
            .init,
            @intCast(self.audio_categories.maxId()),
            entries.items,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateAudioCategories.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateAudioCategories: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateReverbEffectsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = serializer.AssetSerializer(reverb_effect.ReverbEffectAsset);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.reverb_effects.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = entry.value,
            });
        }

        const payload = try asset_packets.UpdateReverbEffects.serialize(
            self.allocator,
            .init,
            @intCast(self.reverb_effects.maxId()),
            entries.items,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateReverbEffects.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateReverbEffects: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateEqualizerEffectsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = serializer.AssetSerializer(equalizer_effect.EqualizerEffectAsset);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.equalizer_effects.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = entry.value,
            });
        }

        const payload = try asset_packets.UpdateEqualizerEffects.serialize(
            self.allocator,
            .init,
            @intCast(self.equalizer_effects.maxId()),
            entries.items,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateEqualizerEffects.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateEqualizerEffects: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateTagPatternsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = serializer.AssetSerializer(tag_pattern.TagPatternAsset);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.tag_patterns.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = entry.value,
            });
        }

        const payload = try asset_packets.UpdateTagPatterns.serialize(
            self.allocator,
            .init,
            @intCast(self.tag_patterns.maxId()),
            entries.items,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateTagPatterns.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateTagPatterns: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateTrailsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        // UpdateTrails uses string keys (Map<String, Trail>) NOT integer keys!
        const S = serializer.StringKeyedSerializer(trail.TrailAsset);

        var entries: std.ArrayList(S.StringKeyedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.trails.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .key = entry.value.id, // Use the trail's ID as the string key
                .value = entry.value,
            });
        }

        const payload = try asset_packets.UpdateTrails.serialize(
            self.allocator,
            .init,
            entries.items,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateTrails.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateTrails: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateEnvironmentsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = serializer.AssetSerializer(asset_packets.UpdateEnvironments.EnvironmentAsset);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.environments.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{ .index = entry.index, .value = entry.value });
        }

        const payload = try asset_packets.UpdateEnvironments.serialize(
            self.allocator,
            .init,
            @intCast(self.environments.maxId()),
            entries.items,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateEnvironments.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateEnvironments: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateEntityEffectsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = serializer.AssetSerializer(entity_effect.EntityEffectAsset);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.entity_effects.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = entry.value,
            });
        }

        const payload = try asset_packets.UpdateEntityEffects.serialize(
            self.allocator,
            .init,
            @intCast(self.entity_effects.maxId()),
            entries.items,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateEntityEffects.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateEntityEffects: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    /// Generate block types packet with basic blocks for flat world
    fn generateBlockTypesPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const BlockTypeAsset = block_type.BlockTypeAsset;
        const BlockTypeEntry = asset_packets.UpdateBlockTypes.BlockTypeEntry;

        // Define basic block types matching constants.BlockId
        // AIR = 0, BEDROCK = 1, STONE = 2, DIRT = 3, GRASS = 4
        var entries: [5]BlockTypeEntry = undefined;
        entries[0] = .{ .id = 0, .block_type = BlockTypeAsset.air() };
        entries[1] = .{ .id = 1, .block_type = try BlockTypeAsset.solid(self.allocator, "Bedrock") };
        entries[2] = .{ .id = 2, .block_type = try BlockTypeAsset.solid(self.allocator, "Stone") };
        entries[3] = .{ .id = 3, .block_type = try BlockTypeAsset.solid(self.allocator, "Dirt") };
        entries[4] = .{ .id = 4, .block_type = try BlockTypeAsset.solid(self.allocator, "Grass") };

        const payload = try asset_packets.UpdateBlockTypes.serialize(
            self.allocator,
            .init,
            4, // maxId = 4 (GRASS)
            &entries,
        );

        try packets.append(self.allocator, .{
            .packet_id = asset_packets.UpdateBlockTypes.PACKET_ID,
            .payload = payload,
        });

        log.debug("Generated UpdateBlockTypes: {d} entries, {d} bytes", .{
            entries.len,
            payload.len,
        });
    }

    /// Generate empty packets for all required asset types not yet implemented
    fn generateEmptyPackets(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        // Asset types that still need empty packets (not implemented yet)
        const all_types = [_]AssetType{
            // .block_types - now generated with data
            .block_hitboxes,
            .block_sound_sets,
            .item_sound_sets,
            .block_particle_sets,
            .block_breaking_decals,
            .block_sets,
            .weathers,
            // .trails - now generated with data
            .particle_systems,
            .particle_spawners,
            // .entity_effects - now generated with data
            .item_player_animations,
            .model_vfxs,
            .items,
            .item_qualities,
            .item_categories,
            .item_reticles,
            .fieldcraft_categories,
            .resource_types,
            .recipes,
            // .environments - now generated with data
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
            // .audio_categories - now generated with data
            // .reverb_effects - now generated with data
            // .equalizer_effects - now generated with data
            .fluids,
            // .tag_patterns - now generated with data
            .projectile_configs,
        };

        for (all_types) |asset_type| {
            const payload = try asset_packets.buildEmptyPacket(self.allocator, asset_type.getPacketId());

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
