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

// Data structures
pub const IndexedAssetMap = @import("indexed_map.zig").IndexedAssetMap;

// Registry and packet generation
pub const AssetRegistry = @import("registry.zig").AssetRegistry;
pub const GeneratedPacket = @import("registry.zig").GeneratedPacket;

// Asset store (ZIP handling)
pub const AssetStore = @import("store.zig").AssetStore;
pub const AssetInfo = @import("store.zig").AssetInfo;

// Packet serialization
pub const packet = @import("packet.zig");

// Helper function to get ZIP path for an asset type
pub const getZipPath = common.getZipPath;

test {
    // Run all submodule tests
    @import("std").testing.refAllDecls(@This());
}
