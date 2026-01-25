/// Asset Management System
///
/// This module handles loading game assets from Assets.zip and serializing them
/// into Update* packets for clients during the loading phase.
///
/// ## Architecture
///
/// ```
/// Assets.zip (JSON files)
///     ↓
/// AssetStore (ZIP reader)
///     ↓
/// IndexedAssetMap (key → index mapping)
///     ↓
/// AssetRegistry (coordinates all stores)
///     ↓
/// Update* packets → Client
/// ```
///
/// ## Usage
///
/// ```zig
/// var registry = AssetRegistry.init(allocator);
/// defer registry.deinit();
///
/// try registry.loadFromZip("HytaleServerSource/Assets.zip");
///
/// var packets = try registry.generateInitPackets();
/// defer {
///     for (packets.items) |p| allocator.free(p.payload);
///     packets.deinit();
/// }
///
/// for (packets.items) |p| {
///     try stream.sendPacket(p.packet_id, p.payload);
/// }
/// ```

// Core types
pub const common = @import("types/common.zig");
pub const UpdateType = common.UpdateType;
pub const AssetType = common.AssetType;
pub const Color = common.Color;
pub const ColorAlpha = common.ColorAlpha;

// Asset type modules
pub const audio_category = @import("types/audio_category.zig");
pub const reverb_effect = @import("types/reverb_effect.zig");
pub const equalizer_effect = @import("types/equalizer_effect.zig");
pub const tag_pattern = @import("types/tag_pattern.zig");
pub const trail = @import("types/trail.zig");

// Asset types
pub const AudioCategoryAsset = audio_category.AudioCategoryAsset;
pub const ReverbEffectAsset = reverb_effect.ReverbEffectAsset;
pub const EqualizerEffectAsset = equalizer_effect.EqualizerEffectAsset;
pub const TagPatternAsset = tag_pattern.TagPatternAsset;
pub const TagPatternType = tag_pattern.TagPatternType;
pub const TrailAsset = trail.TrailAsset;
pub const FXRenderMode = trail.FXRenderMode;
pub const EdgeData = trail.EdgeData;

// JSON parsing utilities
pub const json = @import("json.zig");
pub const dbToLinear = json.dbToLinear;
pub const linearToDb = json.linearToDb;
pub const extractAssetId = json.extractAssetId;

// Data structures
pub const IndexedAssetMap = @import("indexed_map.zig").IndexedAssetMap;

// Registry and packet generation
pub const AssetRegistry = @import("registry.zig").AssetRegistry;
pub const GeneratedPacket = @import("registry.zig").GeneratedPacket;

// Asset store (ZIP handling)
pub const AssetStore = @import("store.zig").AssetStore;
pub const AssetInfo = @import("store.zig").AssetInfo;

// Packet serialization (migrated to protocol/packets/assets/)
pub const packets = @import("../protocol/packets/assets/mod.zig");

// Helper function to get ZIP path for an asset type
pub const getZipPath = common.getZipPath;

test {
    // Run all submodule tests
    @import("std").testing.refAllDecls(@This());
}
