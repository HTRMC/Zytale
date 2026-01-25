/// AssetRegistry - Central coordinator for all game assets
///
/// Manages loading assets from Assets.zip and generating Update* packets
/// to send to clients during the loading phase.

const std = @import("std");
const common = @import("types/common.zig");
const IndexedAssetMap = @import("indexed_map.zig").IndexedAssetMap;
const packet = @import("packet.zig");
const store = @import("store.zig");
const json = @import("json.zig");

// Asset type imports
const audio_category = @import("types/audio_category.zig");
const reverb_effect = @import("types/reverb_effect.zig");
const equalizer_effect = @import("types/equalizer_effect.zig");
const tag_pattern = @import("types/tag_pattern.zig");
const trail = @import("types/trail.zig");

const log = std.log.scoped(.asset_registry);

const UpdateType = common.UpdateType;
const AssetType = common.AssetType;

/// Simple struct for packet serialization (id + volume)
const AudioCategoryEntry = struct {
    id: []const u8,
    volume: f32,
};

/// Simple struct for reverb packet serialization
const ReverbEffectEntry = struct {
    id: []const u8,
    dry_gain: f32,
    modal_density: f32,
    diffusion: f32,
    gain: f32,
    high_frequency_gain: f32,
    decay_time: f32,
    high_frequency_decay_ratio: f32,
    reflection_gain: f32,
    reflection_delay: f32,
    late_reverb_gain: f32,
    late_reverb_delay: f32,
    room_rolloff_factor: f32,
    air_absorption_hf_gain: f32,
    limit_decay_high_frequency: bool,
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
            .audio_categories = IndexedAssetMap(audio_category.AudioCategoryAsset).init(allocator),
            .reverb_effects = IndexedAssetMap(reverb_effect.ReverbEffectAsset).init(allocator),
            .equalizer_effects = IndexedAssetMap(equalizer_effect.EqualizerEffectAsset).init(allocator),
            .tag_patterns = IndexedAssetMap(tag_pattern.TagPatternAsset).init(allocator),
            .trails = IndexedAssetMap(trail.TrailAsset).init(allocator),
            .environments = IndexedAssetMap(packet.EnvironmentAsset).init(allocator),
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
        try self.generateAudioCategoriesPacket(&packets);
        try self.generateReverbEffectsPacket(&packets);
        try self.generateEqualizerEffectsPacket(&packets);
        try self.generateTagPatternsPacket(&packets);
        try self.generateTrailsPacket(&packets);
        try self.generateEnvironmentsPacket(&packets);

        // Generate empty packets for all other required asset types
        try self.generateEmptyPackets(&packets);

        return packets;
    }

    fn generateAudioCategoriesPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = packet.AssetSerializer(packet.AudioCategoryAsset);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.audio_categories.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = .{ .id = entry.value.id, .volume = entry.value.volume },
            });
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

    fn generateReverbEffectsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = packet.AssetSerializer(packet.ReverbEffectAssetType);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.reverb_effects.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = entry.value,
            });
        }

        const payload = try S.serialize(
            self.allocator,
            .init,
            @intCast(self.reverb_effects.maxId()),
            entries.items,
            &[_]u8{},
            packet.serializeReverbEffect,
        );

        try packets.append(self.allocator, .{
            .packet_id = AssetType.reverb_effects.getPacketId(),
            .payload = payload,
        });

        log.debug("Generated UpdateReverbEffects: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateEqualizerEffectsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = packet.AssetSerializer(packet.EqualizerEffectAssetType);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.equalizer_effects.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = entry.value,
            });
        }

        const payload = try S.serialize(
            self.allocator,
            .init,
            @intCast(self.equalizer_effects.maxId()),
            entries.items,
            &[_]u8{},
            packet.serializeEqualizerEffect,
        );

        try packets.append(self.allocator, .{
            .packet_id = AssetType.equalizer_effects.getPacketId(),
            .payload = payload,
        });

        log.debug("Generated UpdateEqualizerEffects: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateTagPatternsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = packet.AssetSerializer(packet.TagPatternAssetType);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.tag_patterns.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .index = entry.index,
                .value = entry.value,
            });
        }

        const payload = try S.serialize(
            self.allocator,
            .init,
            @intCast(self.tag_patterns.maxId()),
            entries.items,
            &[_]u8{},
            packet.serializeTagPattern,
        );

        try packets.append(self.allocator, .{
            .packet_id = AssetType.tag_patterns.getPacketId(),
            .payload = payload,
        });

        log.debug("Generated UpdateTagPatterns: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateTrailsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        // UpdateTrails uses string keys (Map<String, Trail>) NOT integer keys!
        const S = packet.StringKeyedSerializer(packet.TrailAssetType);

        var entries: std.ArrayList(S.StringKeyedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.trails.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{
                .key = entry.value.id, // Use the trail's ID as the string key
                .value = entry.value,
            });
        }

        const payload = try S.serialize(
            self.allocator,
            .init,
            entries.items,
            packet.serializeTrail,
        );

        try packets.append(self.allocator, .{
            .packet_id = AssetType.trails.getPacketId(),
            .payload = payload,
        });

        log.debug("Generated UpdateTrails: {d} entries, {d} bytes", .{
            entries.items.len,
            payload.len,
        });
    }

    fn generateEnvironmentsPacket(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        const S = packet.AssetSerializer(packet.EnvironmentAsset);

        var entries: std.ArrayList(S.IndexedEntry) = .empty;
        defer entries.deinit(self.allocator);

        var iter = self.environments.constIterator();
        while (iter.next()) |entry| {
            try entries.append(self.allocator, .{ .index = entry.index, .value = entry.value });
        }

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

    /// Generate empty packets for all required asset types not yet implemented
    fn generateEmptyPackets(self: *Self, packets: *std.ArrayList(GeneratedPacket)) !void {
        // Debug: Helper to print hex dump for specific asset types
        const debugHexDump = struct {
            fn dump(asset_type: AssetType, payload: []const u8) void {
                // Only dump for debugging specific packets
                if (asset_type == .entity_effects or
                    asset_type == .block_sound_sets or
                    asset_type == .item_player_animations)
                {
                    std.debug.print("DEBUG {s} (ID {d}, {d} bytes): ", .{
                        @tagName(asset_type),
                        asset_type.getPacketId(),
                        payload.len,
                    });
                    for (payload) |b| {
                        std.debug.print("{x:0>2} ", .{b});
                    }
                    std.debug.print("\n", .{});
                }
            }
        }.dump;

        // Asset types that still need empty packets (not implemented yet)
        const all_types = [_]AssetType{
            .block_types,
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
            const payload = try packet.buildEmptyUpdatePacket(self.allocator, asset_type);

            // Debug: print hex dump for specific troublesome packets
            debugHexDump(asset_type, payload);

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
