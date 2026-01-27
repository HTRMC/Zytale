/// Asset Update Packets (IDs 40-85)
///
/// This module re-exports all Update* packet definitions.
/// Each packet mirrors the corresponding Java class in com/hypixel/hytale/protocol/packets/assets/

const std = @import("std");

// Generic serialization utilities
pub const serializer = @import("serializer.zig");

// ============================================================================
// Implemented packets (with full serialization)
// ============================================================================
pub const UpdateAudioCategories = @import("UpdateAudioCategories.zig");
pub const UpdateReverbEffects = @import("UpdateReverbEffects.zig");
pub const UpdateEqualizerEffects = @import("UpdateEqualizerEffects.zig");
pub const UpdateTagPatterns = @import("UpdateTagPatterns.zig");
pub const UpdateTrails = @import("UpdateTrails.zig");
pub const UpdateEntityEffects = @import("UpdateEntityEffects.zig");
pub const UpdateEnvironments = @import("UpdateEnvironments.zig");
pub const UpdateBlockTypes = @import("UpdateBlockTypes.zig");

// ============================================================================
// Packets with custom serialize (no buildEmptyPacket)
// ============================================================================
pub const UpdateBlockHitboxes = @import("UpdateBlockHitboxes.zig");
pub const UpdateBlockSoundSets = @import("UpdateBlockSoundSets.zig");
pub const UpdateItemSoundSets = @import("UpdateItemSoundSets.zig");
pub const UpdateBlockParticleSets = @import("UpdateBlockParticleSets.zig");
pub const UpdateBlockBreakingDecals = @import("UpdateBlockBreakingDecals.zig");
pub const UpdateBlockSets = @import("UpdateBlockSets.zig");
pub const UpdateWeathers = @import("UpdateWeathers.zig");
pub const UpdateParticleSystems = @import("UpdateParticleSystems.zig");
pub const UpdateParticleSpawners = @import("UpdateParticleSpawners.zig");
pub const UpdateItemPlayerAnimations = @import("UpdateItemPlayerAnimations.zig");
pub const UpdateModelvfxs = @import("UpdateModelvfxs.zig");
pub const UpdateItems = @import("UpdateItems.zig");
pub const UpdateItemQualities = @import("UpdateItemQualities.zig");
pub const UpdateItemCategories = @import("UpdateItemCategories.zig");
pub const UpdateItemReticles = @import("UpdateItemReticles.zig");
pub const UpdateFieldcraftCategories = @import("UpdateFieldcraftCategories.zig");
pub const UpdateResourceTypes = @import("UpdateResourceTypes.zig");
pub const UpdateRecipes = @import("UpdateRecipes.zig");
pub const UpdateAmbienceFX = @import("UpdateAmbienceFX.zig");
pub const UpdateFluidFX = @import("UpdateFluidFX.zig");
pub const UpdateTranslations = @import("UpdateTranslations.zig");
pub const UpdateSoundEvents = @import("UpdateSoundEvents.zig");
pub const UpdateInteractions = @import("UpdateInteractions.zig");
pub const UpdateRootInteractions = @import("UpdateRootInteractions.zig");
pub const UpdateUnarmedInteractions = @import("UpdateUnarmedInteractions.zig");
pub const UpdateEntityStatTypes = @import("UpdateEntityStatTypes.zig");
pub const UpdateEntityUIComponents = @import("UpdateEntityUIComponents.zig");
pub const UpdateHitboxCollisionConfig = @import("UpdateHitboxCollisionConfig.zig");
pub const UpdateRepulsionConfig = @import("UpdateRepulsionConfig.zig");
pub const UpdateViewBobbing = @import("UpdateViewBobbing.zig");
pub const UpdateCameraShake = @import("UpdateCameraShake.zig");
pub const UpdateBlockGroups = @import("UpdateBlockGroups.zig");
pub const UpdateSoundSets = @import("UpdateSoundSets.zig");
pub const UpdateFluids = @import("UpdateFluids.zig");
pub const UpdateProjectileConfigs = @import("UpdateProjectileConfigs.zig");

// ============================================================================
// Re-export commonly used types
// ============================================================================
pub const AssetSerializer = serializer.AssetSerializer;
pub const StringKeyedSerializer = serializer.StringKeyedSerializer;
pub const UpdateType = serializer.UpdateType;

// ============================================================================
// Convenience functions
// ============================================================================

/// Build an empty Update* packet for a given asset type
/// Packet IDs match protocol registry (asset packets: 40-85)
/// Note: Java packet generators always create empty collections (not null),
/// so we pass empty slices (&.{}) to set nullBits=1 with count=0.
pub fn buildEmptyPacket(allocator: std.mem.Allocator, packet_id: u32) ![]u8 {
    return switch (packet_id) {
        // Packets with max_id parameter (int-keyed dictionaries)
        40 => UpdateBlockTypes.serialize(allocator, .init, 0, &.{}),
        41 => UpdateBlockHitboxes.serialize(allocator, .init, 0, &.{}),
        42 => UpdateBlockSoundSets.serialize(allocator, .init, 0, &.{}),
        43 => UpdateItemSoundSets.serialize(allocator, .init, 0, &.{}),
        47 => UpdateWeathers.serialize(allocator, .init, 0, &.{}),
        53 => UpdateModelvfxs.serialize(allocator, .init, 0, &.{}),
        55 => UpdateItemQualities.serialize(allocator, .init, 0, &.{}),
        57 => UpdateItemReticles.serialize(allocator, .init, 0, &.{}),
        62 => UpdateAmbienceFX.serialize(allocator, .init, 0, &.{}),
        63 => UpdateFluidFX.serialize(allocator, .init, 0, &.{}),
        65 => UpdateSoundEvents.serialize(allocator, .init, 0, &.{}),
        66 => UpdateInteractions.serialize(allocator, .init, 0, &.{}),
        67 => UpdateRootInteractions.serialize(allocator, .init, 0, &.{}),
        72 => UpdateEntityStatTypes.serialize(allocator, .init, 0, &.{}),
        73 => UpdateEntityUIComponents.serialize(allocator, .init, 0, &.{}),
        74 => UpdateHitboxCollisionConfig.serialize(allocator, .init, 0, &.{}),
        75 => UpdateRepulsionConfig.serialize(allocator, .init, 0, &.{}),
        79 => UpdateSoundSets.serialize(allocator, .init, 0, &.{}),
        83 => UpdateFluids.serialize(allocator, .init, 0, &.{}),

        // Packets without max_id (string-keyed dictionaries)
        44 => UpdateBlockParticleSets.serialize(allocator, .init, &.{}),
        45 => UpdateBlockBreakingDecals.serialize(allocator, .init, &.{}),
        46 => UpdateBlockSets.serialize(allocator, .init, &.{}),
        52 => UpdateItemPlayerAnimations.serialize(allocator, .init, &.{}),
        59 => UpdateResourceTypes.serialize(allocator, .init, &.{}),
        64 => UpdateTranslations.serialize(allocator, .init, &.{}),
        68 => UpdateUnarmedInteractions.serialize(allocator, .init, &.{}),
        78 => UpdateBlockGroups.serialize(allocator, .init, &.{}),

        // Packets with offset-based variable fields
        // For init packets: main dictionary = empty slice, removed array = null
        // This matches Java: empty HashMap for data, null for removed field
        49 => UpdateParticleSystems.serialize(allocator, .init, &.{}, null),
        50 => UpdateParticleSpawners.serialize(allocator, .init, &.{}, null),
        54 => UpdateItems.serialize(allocator, .init, false, false, &.{}, null),
        60 => UpdateRecipes.serialize(allocator, .init, &.{}, null),
        85 => UpdateProjectileConfigs.serialize(allocator, .init, &.{}, null),

        // Packets using generic serializers (keep buildEmptyPacket)
        48 => UpdateTrails.buildEmptyPacket(allocator),
        51 => UpdateEntityEffects.buildEmptyPacket(allocator),
        56 => UpdateItemCategories.buildEmptyPacket(allocator),
        58 => UpdateFieldcraftCategories.buildEmptyPacket(allocator),
        61 => UpdateEnvironments.buildEmptyPacket(allocator),
        76 => UpdateViewBobbing.buildEmptyPacket(allocator),
        77 => UpdateCameraShake.buildEmptyPacket(allocator),
        80 => UpdateAudioCategories.buildEmptyPacket(allocator),
        81 => UpdateReverbEffects.buildEmptyPacket(allocator),
        82 => UpdateEqualizerEffects.buildEmptyPacket(allocator),
        84 => UpdateTagPatterns.buildEmptyPacket(allocator),

        // 69-71 are objective tracking packets, not asset packets
        else => error.UnknownPacketId,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "all packet modules compile" {
    // Ensure all modules can be imported
    _ = serializer;
    _ = UpdateAudioCategories;
    _ = UpdateReverbEffects;
    _ = UpdateEqualizerEffects;
    _ = UpdateTagPatterns;
    _ = UpdateTrails;
    _ = UpdateEntityEffects;
    _ = UpdateEnvironments;
    _ = UpdateBlockTypes;
    _ = UpdateBlockHitboxes;
    _ = UpdateBlockSoundSets;
    _ = UpdateItemSoundSets;
    _ = UpdateBlockParticleSets;
    _ = UpdateBlockBreakingDecals;
    _ = UpdateBlockSets;
    _ = UpdateWeathers;
    _ = UpdateParticleSystems;
    _ = UpdateParticleSpawners;
    _ = UpdateItemPlayerAnimations;
    _ = UpdateModelvfxs;
    _ = UpdateItems;
    _ = UpdateItemQualities;
    _ = UpdateItemCategories;
    _ = UpdateItemReticles;
    _ = UpdateFieldcraftCategories;
    _ = UpdateResourceTypes;
    _ = UpdateRecipes;
    _ = UpdateAmbienceFX;
    _ = UpdateFluidFX;
    _ = UpdateTranslations;
    _ = UpdateSoundEvents;
    _ = UpdateInteractions;
    _ = UpdateRootInteractions;
    _ = UpdateUnarmedInteractions;
    _ = UpdateEntityStatTypes;
    _ = UpdateEntityUIComponents;
    _ = UpdateHitboxCollisionConfig;
    _ = UpdateRepulsionConfig;
    _ = UpdateViewBobbing;
    _ = UpdateCameraShake;
    _ = UpdateBlockGroups;
    _ = UpdateSoundSets;
    _ = UpdateFluids;
    _ = UpdateProjectileConfigs;
}

test "buildEmptyPacket for common types" {
    const allocator = std.testing.allocator;

    // Test a few representative packet types
    const audio_pkt = try buildEmptyPacket(allocator, 80);
    defer allocator.free(audio_pkt);
    try std.testing.expectEqual(@as(usize, 7), audio_pkt.len);

    // Trails is packet ID 48 (uses generic serializer)
    const trails_pkt = try buildEmptyPacket(allocator, 48);
    defer allocator.free(trails_pkt);
    try std.testing.expectEqual(@as(usize, 3), trails_pkt.len);

    // BlockTypes uses serialize with empty slice (nullBits=1, count=0)
    // Size: 10 bytes fixed + 1 byte VarInt(0) = 11 bytes
    const blocks_pkt = try buildEmptyPacket(allocator, 40);
    defer allocator.free(blocks_pkt);
    try std.testing.expectEqual(@as(usize, 11), blocks_pkt.len);
}
