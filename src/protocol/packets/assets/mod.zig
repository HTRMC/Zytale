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

// ============================================================================
// Placeholder packets (buildEmptyPacket only)
// ============================================================================
pub const UpdateBlockTypes = @import("UpdateBlockTypes.zig");
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
pub fn buildEmptyPacket(allocator: std.mem.Allocator, packet_id: u32) ![]u8 {
    return switch (packet_id) {
        40 => UpdateBlockTypes.buildEmptyPacket(allocator),
        41 => UpdateBlockHitboxes.buildEmptyPacket(allocator),
        42 => UpdateBlockSoundSets.buildEmptyPacket(allocator),
        43 => UpdateItemSoundSets.buildEmptyPacket(allocator),
        44 => UpdateBlockParticleSets.buildEmptyPacket(allocator),
        45 => UpdateBlockBreakingDecals.buildEmptyPacket(allocator),
        46 => UpdateBlockSets.buildEmptyPacket(allocator),
        47 => UpdateWeathers.buildEmptyPacket(allocator),
        48 => UpdateParticleSystems.buildEmptyPacket(allocator),
        49 => UpdateParticleSpawners.buildEmptyPacket(allocator),
        50 => UpdateEntityEffects.buildEmptyPacket(allocator),
        51 => UpdateTrails.buildEmptyPacket(allocator),
        52 => UpdateItemPlayerAnimations.buildEmptyPacket(allocator),
        53 => UpdateModelvfxs.buildEmptyPacket(allocator),
        54 => UpdateItems.buildEmptyPacket(allocator),
        55 => UpdateItemQualities.buildEmptyPacket(allocator),
        56 => UpdateItemCategories.buildEmptyPacket(allocator),
        57 => UpdateItemReticles.buildEmptyPacket(allocator),
        58 => UpdateFieldcraftCategories.buildEmptyPacket(allocator),
        59 => UpdateResourceTypes.buildEmptyPacket(allocator),
        60 => UpdateRecipes.buildEmptyPacket(allocator),
        61 => UpdateEnvironments.buildEmptyPacket(allocator),
        62 => UpdateAmbienceFX.buildEmptyPacket(allocator),
        63 => UpdateFluidFX.buildEmptyPacket(allocator),
        64 => UpdateTranslations.buildEmptyPacket(allocator),
        65 => UpdateSoundEvents.buildEmptyPacket(allocator),
        66 => UpdateInteractions.buildEmptyPacket(allocator),
        67 => UpdateRootInteractions.buildEmptyPacket(allocator),
        68 => UpdateUnarmedInteractions.buildEmptyPacket(allocator),
        69 => UpdateEntityStatTypes.buildEmptyPacket(allocator),
        70 => UpdateEntityUIComponents.buildEmptyPacket(allocator),
        71 => UpdateHitboxCollisionConfig.buildEmptyPacket(allocator),
        72 => UpdateRepulsionConfig.buildEmptyPacket(allocator),
        73 => UpdateViewBobbing.buildEmptyPacket(allocator),
        74 => UpdateCameraShake.buildEmptyPacket(allocator),
        75 => UpdateBlockGroups.buildEmptyPacket(allocator),
        76 => UpdateSoundSets.buildEmptyPacket(allocator),
        80 => UpdateAudioCategories.buildEmptyPacket(allocator),
        81 => UpdateReverbEffects.buildEmptyPacket(allocator),
        82 => UpdateEqualizerEffects.buildEmptyPacket(allocator),
        83 => UpdateFluids.buildEmptyPacket(allocator),
        84 => UpdateTagPatterns.buildEmptyPacket(allocator),
        85 => UpdateProjectileConfigs.buildEmptyPacket(allocator),
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

    const trails_pkt = try buildEmptyPacket(allocator, 51);
    defer allocator.free(trails_pkt);
    try std.testing.expectEqual(@as(usize, 3), trails_pkt.len);

    const blocks_pkt = try buildEmptyPacket(allocator, 40);
    defer allocator.free(blocks_pkt);
    try std.testing.expectEqual(@as(usize, 11), blocks_pkt.len);
}
