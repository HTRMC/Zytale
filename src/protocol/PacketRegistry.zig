/// Hytale Packet Registry
/// Auto-generated from Java PacketRegistry.java
///
/// Each packet has:
/// - id: Unique packet identifier
/// - name: Human-readable name
/// - min_size: Minimum payload size (fixedBlockSize)
/// - max_size: Maximum payload size
/// - compressed: Whether payload is Zstd compressed

pub const PacketInfo = struct {
    id: u32,
    name: []const u8,
    min_size: u32,
    max_size: u32,
    compressed: bool,
};

/// Packet categories
pub const Category = enum {
    connection,
    auth,
    setup,
    assets,
    player,
    world,
    entities,
    inventory,
    window,
    interface,
    worldmap,
    serveraccess,
    machinima,
    camera,
    interaction,
    asseteditor,
    buildertools,
};

// ============================================
// CONNECTION PACKETS (0-3)
// ============================================
pub const Connect: PacketInfo = .{ .id = 0, .name = "Connect", .min_size = 82, .max_size = 38161, .compressed = false };
pub const Disconnect: PacketInfo = .{ .id = 1, .name = "Disconnect", .min_size = 2, .max_size = 16384007, .compressed = false };
pub const Ping: PacketInfo = .{ .id = 2, .name = "Ping", .min_size = 29, .max_size = 29, .compressed = false };
pub const Pong: PacketInfo = .{ .id = 3, .name = "Pong", .min_size = 20, .max_size = 20, .compressed = false };

// ============================================
// AUTH PACKETS (10-18)
// ============================================
pub const Status: PacketInfo = .{ .id = 10, .name = "Status", .min_size = 9, .max_size = 2587, .compressed = false };
pub const AuthGrant: PacketInfo = .{ .id = 11, .name = "AuthGrant", .min_size = 1, .max_size = 49171, .compressed = false };
pub const AuthToken: PacketInfo = .{ .id = 12, .name = "AuthToken", .min_size = 1, .max_size = 49171, .compressed = false };
pub const ServerAuthToken: PacketInfo = .{ .id = 13, .name = "ServerAuthToken", .min_size = 1, .max_size = 32851, .compressed = false };
pub const ConnectAccept: PacketInfo = .{ .id = 14, .name = "ConnectAccept", .min_size = 1, .max_size = 70, .compressed = false };
pub const PasswordResponse: PacketInfo = .{ .id = 15, .name = "PasswordResponse", .min_size = 1, .max_size = 70, .compressed = false };
pub const PasswordAccepted: PacketInfo = .{ .id = 16, .name = "PasswordAccepted", .min_size = 0, .max_size = 0, .compressed = false };
pub const PasswordRejected: PacketInfo = .{ .id = 17, .name = "PasswordRejected", .min_size = 5, .max_size = 74, .compressed = false };
pub const ClientReferral: PacketInfo = .{ .id = 18, .name = "ClientReferral", .min_size = 1, .max_size = 5141, .compressed = false };

// ============================================
// SETUP PACKETS (20-34)
// ============================================
pub const WorldSettings: PacketInfo = .{ .id = 20, .name = "WorldSettings", .min_size = 5, .max_size = 1677721600, .compressed = true };
pub const WorldLoadProgress: PacketInfo = .{ .id = 21, .name = "WorldLoadProgress", .min_size = 9, .max_size = 16384014, .compressed = false };
pub const WorldLoadFinished: PacketInfo = .{ .id = 22, .name = "WorldLoadFinished", .min_size = 0, .max_size = 0, .compressed = false };
pub const RequestAssets: PacketInfo = .{ .id = 23, .name = "RequestAssets", .min_size = 1, .max_size = 1677721600, .compressed = true };
pub const AssetInitialize: PacketInfo = .{ .id = 24, .name = "AssetInitialize", .min_size = 4, .max_size = 2121, .compressed = false };
pub const AssetPart: PacketInfo = .{ .id = 25, .name = "AssetPart", .min_size = 1, .max_size = 4096006, .compressed = true };
pub const AssetFinalize: PacketInfo = .{ .id = 26, .name = "AssetFinalize", .min_size = 0, .max_size = 0, .compressed = false };
pub const RemoveAssets: PacketInfo = .{ .id = 27, .name = "RemoveAssets", .min_size = 1, .max_size = 1677721600, .compressed = false };
pub const RequestCommonAssetsRebuild: PacketInfo = .{ .id = 28, .name = "RequestCommonAssetsRebuild", .min_size = 0, .max_size = 0, .compressed = false };
pub const SetUpdateRate: PacketInfo = .{ .id = 29, .name = "SetUpdateRate", .min_size = 4, .max_size = 4, .compressed = false };
pub const SetTimeDilation: PacketInfo = .{ .id = 30, .name = "SetTimeDilation", .min_size = 4, .max_size = 4, .compressed = false };
pub const UpdateFeatures: PacketInfo = .{ .id = 31, .name = "UpdateFeatures", .min_size = 1, .max_size = 8192006, .compressed = false };
pub const ViewRadius: PacketInfo = .{ .id = 32, .name = "ViewRadius", .min_size = 4, .max_size = 4, .compressed = false };
pub const PlayerOptions: PacketInfo = .{ .id = 33, .name = "PlayerOptions", .min_size = 1, .max_size = 327680184, .compressed = false };
pub const ServerTags: PacketInfo = .{ .id = 34, .name = "ServerTags", .min_size = 1, .max_size = 1677721600, .compressed = false };

// ============================================
// ASSET UPDATE PACKETS (40-85)
// ============================================
pub const UpdateBlockTypes: PacketInfo = .{ .id = 40, .name = "UpdateBlockTypes", .min_size = 10, .max_size = 1677721600, .compressed = true };
pub const UpdateBlockHitboxes: PacketInfo = .{ .id = 41, .name = "UpdateBlockHitboxes", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateBlockSoundSets: PacketInfo = .{ .id = 42, .name = "UpdateBlockSoundSets", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateItemSoundSets: PacketInfo = .{ .id = 43, .name = "UpdateItemSoundSets", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateBlockParticleSets: PacketInfo = .{ .id = 44, .name = "UpdateBlockParticleSets", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateBlockBreakingDecals: PacketInfo = .{ .id = 45, .name = "UpdateBlockBreakingDecals", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateBlockSets: PacketInfo = .{ .id = 46, .name = "UpdateBlockSets", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateWeathers: PacketInfo = .{ .id = 47, .name = "UpdateWeathers", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateTrails: PacketInfo = .{ .id = 48, .name = "UpdateTrails", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateParticleSystems: PacketInfo = .{ .id = 49, .name = "UpdateParticleSystems", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateParticleSpawners: PacketInfo = .{ .id = 50, .name = "UpdateParticleSpawners", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateEntityEffects: PacketInfo = .{ .id = 51, .name = "UpdateEntityEffects", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateItemPlayerAnimations: PacketInfo = .{ .id = 52, .name = "UpdateItemPlayerAnimations", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateModelvfxs: PacketInfo = .{ .id = 53, .name = "UpdateModelvfxs", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateItems: PacketInfo = .{ .id = 54, .name = "UpdateItems", .min_size = 4, .max_size = 1677721600, .compressed = true };
pub const UpdateItemQualities: PacketInfo = .{ .id = 55, .name = "UpdateItemQualities", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateItemCategories: PacketInfo = .{ .id = 56, .name = "UpdateItemCategories", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateItemReticles: PacketInfo = .{ .id = 57, .name = "UpdateItemReticles", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateFieldcraftCategories: PacketInfo = .{ .id = 58, .name = "UpdateFieldcraftCategories", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateResourceTypes: PacketInfo = .{ .id = 59, .name = "UpdateResourceTypes", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateRecipes: PacketInfo = .{ .id = 60, .name = "UpdateRecipes", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateEnvironments: PacketInfo = .{ .id = 61, .name = "UpdateEnvironments", .min_size = 7, .max_size = 1677721600, .compressed = true };
pub const UpdateAmbienceFX: PacketInfo = .{ .id = 62, .name = "UpdateAmbienceFX", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateFluidFX: PacketInfo = .{ .id = 63, .name = "UpdateFluidFX", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateTranslations: PacketInfo = .{ .id = 64, .name = "UpdateTranslations", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateSoundEvents: PacketInfo = .{ .id = 65, .name = "UpdateSoundEvents", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateInteractions: PacketInfo = .{ .id = 66, .name = "UpdateInteractions", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateRootInteractions: PacketInfo = .{ .id = 67, .name = "UpdateRootInteractions", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateUnarmedInteractions: PacketInfo = .{ .id = 68, .name = "UpdateUnarmedInteractions", .min_size = 2, .max_size = 20480007, .compressed = true };
pub const TrackOrUpdateObjective: PacketInfo = .{ .id = 69, .name = "TrackOrUpdateObjective", .min_size = 1, .max_size = 1677721600, .compressed = false };
pub const UntrackObjective: PacketInfo = .{ .id = 70, .name = "UntrackObjective", .min_size = 16, .max_size = 16, .compressed = false };
pub const UpdateObjectiveTask: PacketInfo = .{ .id = 71, .name = "UpdateObjectiveTask", .min_size = 21, .max_size = 16384035, .compressed = false };
pub const UpdateEntityStatTypes: PacketInfo = .{ .id = 72, .name = "UpdateEntityStatTypes", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateEntityUIComponents: PacketInfo = .{ .id = 73, .name = "UpdateEntityUIComponents", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateHitboxCollisionConfig: PacketInfo = .{ .id = 74, .name = "UpdateHitboxCollisionConfig", .min_size = 6, .max_size = 36864011, .compressed = true };
pub const UpdateRepulsionConfig: PacketInfo = .{ .id = 75, .name = "UpdateRepulsionConfig", .min_size = 6, .max_size = 65536011, .compressed = true };
pub const UpdateViewBobbing: PacketInfo = .{ .id = 76, .name = "UpdateViewBobbing", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateCameraShake: PacketInfo = .{ .id = 77, .name = "UpdateCameraShake", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateBlockGroups: PacketInfo = .{ .id = 78, .name = "UpdateBlockGroups", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const UpdateSoundSets: PacketInfo = .{ .id = 79, .name = "UpdateSoundSets", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateAudioCategories: PacketInfo = .{ .id = 80, .name = "UpdateAudioCategories", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateReverbEffects: PacketInfo = .{ .id = 81, .name = "UpdateReverbEffects", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateEqualizerEffects: PacketInfo = .{ .id = 82, .name = "UpdateEqualizerEffects", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateFluids: PacketInfo = .{ .id = 83, .name = "UpdateFluids", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateTagPatterns: PacketInfo = .{ .id = 84, .name = "UpdateTagPatterns", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateProjectileConfigs: PacketInfo = .{ .id = 85, .name = "UpdateProjectileConfigs", .min_size = 2, .max_size = 1677721600, .compressed = true };

// ============================================
// PLAYER PACKETS (100-119)
// ============================================
pub const SetClientId: PacketInfo = .{ .id = 100, .name = "SetClientId", .min_size = 4, .max_size = 4, .compressed = false };
pub const SetGameMode: PacketInfo = .{ .id = 101, .name = "SetGameMode", .min_size = 1, .max_size = 1, .compressed = false };
pub const SetMovementStates: PacketInfo = .{ .id = 102, .name = "SetMovementStates", .min_size = 2, .max_size = 2, .compressed = false };
pub const SetBlockPlacementOverride: PacketInfo = .{ .id = 103, .name = "SetBlockPlacementOverride", .min_size = 1, .max_size = 1, .compressed = false };
pub const JoinWorld: PacketInfo = .{ .id = 104, .name = "JoinWorld", .min_size = 18, .max_size = 18, .compressed = false };
pub const ClientReady: PacketInfo = .{ .id = 105, .name = "ClientReady", .min_size = 2, .max_size = 2, .compressed = false };
pub const LoadHotbar: PacketInfo = .{ .id = 106, .name = "LoadHotbar", .min_size = 1, .max_size = 1, .compressed = false };
pub const SaveHotbar: PacketInfo = .{ .id = 107, .name = "SaveHotbar", .min_size = 1, .max_size = 1, .compressed = false };
pub const ClientMovement: PacketInfo = .{ .id = 108, .name = "ClientMovement", .min_size = 153, .max_size = 153, .compressed = false };
pub const ClientTeleport: PacketInfo = .{ .id = 109, .name = "ClientTeleport", .min_size = 52, .max_size = 52, .compressed = false };
pub const UpdateMovementSettings: PacketInfo = .{ .id = 110, .name = "UpdateMovementSettings", .min_size = 252, .max_size = 252, .compressed = false };
pub const MouseInteraction: PacketInfo = .{ .id = 111, .name = "MouseInteraction", .min_size = 44, .max_size = 20480071, .compressed = false };
pub const DamageInfo: PacketInfo = .{ .id = 112, .name = "DamageInfo", .min_size = 29, .max_size = 32768048, .compressed = false };
pub const ReticleEvent: PacketInfo = .{ .id = 113, .name = "ReticleEvent", .min_size = 4, .max_size = 4, .compressed = false };
pub const DisplayDebug: PacketInfo = .{ .id = 114, .name = "DisplayDebug", .min_size = 19, .max_size = 32768037, .compressed = false };
pub const ClearDebugShapes: PacketInfo = .{ .id = 115, .name = "ClearDebugShapes", .min_size = 0, .max_size = 0, .compressed = false };
pub const SyncPlayerPreferences: PacketInfo = .{ .id = 116, .name = "SyncPlayerPreferences", .min_size = 8, .max_size = 8, .compressed = false };
pub const ClientPlaceBlock: PacketInfo = .{ .id = 117, .name = "ClientPlaceBlock", .min_size = 20, .max_size = 20, .compressed = false };
pub const UpdateMemoriesFeatureStatus: PacketInfo = .{ .id = 118, .name = "UpdateMemoriesFeatureStatus", .min_size = 1, .max_size = 1, .compressed = false };
pub const RemoveMapMarker: PacketInfo = .{ .id = 119, .name = "RemoveMapMarker", .min_size = 1, .max_size = 16384006, .compressed = false };

// ============================================
// CHUNK/WORLD PACKETS (131-166)
// ============================================
pub const SetChunk: PacketInfo = .{ .id = 131, .name = "SetChunk", .min_size = 13, .max_size = 12288040, .compressed = true };
pub const SetChunkHeightmap: PacketInfo = .{ .id = 132, .name = "SetChunkHeightmap", .min_size = 9, .max_size = 4096014, .compressed = true };
pub const SetChunkTintmap: PacketInfo = .{ .id = 133, .name = "SetChunkTintmap", .min_size = 9, .max_size = 4096014, .compressed = true };
pub const SetChunkEnvironments: PacketInfo = .{ .id = 134, .name = "SetChunkEnvironments", .min_size = 9, .max_size = 4096014, .compressed = true };
pub const UnloadChunk: PacketInfo = .{ .id = 135, .name = "UnloadChunk", .min_size = 8, .max_size = 8, .compressed = false };
pub const SetFluids: PacketInfo = .{ .id = 136, .name = "SetFluids", .min_size = 13, .max_size = 4096018, .compressed = true };
pub const ServerSetBlock: PacketInfo = .{ .id = 140, .name = "ServerSetBlock", .min_size = 19, .max_size = 19, .compressed = false };
pub const ServerSetBlocks: PacketInfo = .{ .id = 141, .name = "ServerSetBlocks", .min_size = 12, .max_size = 36864017, .compressed = false };
pub const ServerSetFluid: PacketInfo = .{ .id = 142, .name = "ServerSetFluid", .min_size = 17, .max_size = 17, .compressed = false };
pub const ServerSetFluids: PacketInfo = .{ .id = 143, .name = "ServerSetFluids", .min_size = 12, .max_size = 28672017, .compressed = false };
pub const UpdateBlockDamage: PacketInfo = .{ .id = 144, .name = "UpdateBlockDamage", .min_size = 21, .max_size = 21, .compressed = false };
pub const UpdateTimeSettings: PacketInfo = .{ .id = 145, .name = "UpdateTimeSettings", .min_size = 10, .max_size = 10, .compressed = false };
pub const UpdateTime: PacketInfo = .{ .id = 146, .name = "UpdateTime", .min_size = 13, .max_size = 13, .compressed = false };
pub const UpdateEditorTimeOverride: PacketInfo = .{ .id = 147, .name = "UpdateEditorTimeOverride", .min_size = 14, .max_size = 14, .compressed = false };
pub const ClearEditorTimeOverride: PacketInfo = .{ .id = 148, .name = "ClearEditorTimeOverride", .min_size = 0, .max_size = 0, .compressed = false };
pub const UpdateWeather: PacketInfo = .{ .id = 149, .name = "UpdateWeather", .min_size = 8, .max_size = 8, .compressed = false };
pub const UpdateEditorWeatherOverride: PacketInfo = .{ .id = 150, .name = "UpdateEditorWeatherOverride", .min_size = 4, .max_size = 4, .compressed = false };
pub const UpdateEnvironmentMusic: PacketInfo = .{ .id = 151, .name = "UpdateEnvironmentMusic", .min_size = 4, .max_size = 4, .compressed = false };
pub const SpawnParticleSystem: PacketInfo = .{ .id = 152, .name = "SpawnParticleSystem", .min_size = 44, .max_size = 16384049, .compressed = false };
pub const SpawnBlockParticleSystem: PacketInfo = .{ .id = 153, .name = "SpawnBlockParticleSystem", .min_size = 30, .max_size = 30, .compressed = false };
pub const PlaySoundEvent2D: PacketInfo = .{ .id = 154, .name = "PlaySoundEvent2D", .min_size = 13, .max_size = 13, .compressed = false };
pub const PlaySoundEvent3D: PacketInfo = .{ .id = 155, .name = "PlaySoundEvent3D", .min_size = 38, .max_size = 38, .compressed = false };
pub const PlaySoundEventEntity: PacketInfo = .{ .id = 156, .name = "PlaySoundEventEntity", .min_size = 16, .max_size = 16, .compressed = false };
pub const UpdateSleepState: PacketInfo = .{ .id = 157, .name = "UpdateSleepState", .min_size = 36, .max_size = 65536050, .compressed = false };
pub const SetPaused: PacketInfo = .{ .id = 158, .name = "SetPaused", .min_size = 1, .max_size = 1, .compressed = false };
pub const ServerSetPaused: PacketInfo = .{ .id = 159, .name = "ServerSetPaused", .min_size = 1, .max_size = 1, .compressed = false };

// ============================================
// ENTITY PACKETS (160-166)
// ============================================
pub const SetEntitySeed: PacketInfo = .{ .id = 160, .name = "SetEntitySeed", .min_size = 4, .max_size = 4, .compressed = false };
pub const EntityUpdates: PacketInfo = .{ .id = 161, .name = "EntityUpdates", .min_size = 1, .max_size = 1677721600, .compressed = true };
pub const PlayAnimation: PacketInfo = .{ .id = 162, .name = "PlayAnimation", .min_size = 6, .max_size = 32768024, .compressed = false };
pub const ChangeVelocity: PacketInfo = .{ .id = 163, .name = "ChangeVelocity", .min_size = 35, .max_size = 35, .compressed = false };
pub const ApplyKnockback: PacketInfo = .{ .id = 164, .name = "ApplyKnockback", .min_size = 38, .max_size = 38, .compressed = false };
pub const SpawnModelParticles: PacketInfo = .{ .id = 165, .name = "SpawnModelParticles", .min_size = 5, .max_size = 1677721600, .compressed = false };
pub const MountMovement: PacketInfo = .{ .id = 166, .name = "MountMovement", .min_size = 59, .max_size = 59, .compressed = false };

// ============================================
// INVENTORY PACKETS (170-179)
// ============================================
pub const UpdatePlayerInventory: PacketInfo = .{ .id = 170, .name = "UpdatePlayerInventory", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const SetCreativeItem: PacketInfo = .{ .id = 171, .name = "SetCreativeItem", .min_size = 9, .max_size = 16384019, .compressed = false };
pub const DropCreativeItem: PacketInfo = .{ .id = 172, .name = "DropCreativeItem", .min_size = 0, .max_size = 16384010, .compressed = false };
pub const SmartGiveCreativeItem: PacketInfo = .{ .id = 173, .name = "SmartGiveCreativeItem", .min_size = 1, .max_size = 16384011, .compressed = false };
pub const DropItemStack: PacketInfo = .{ .id = 174, .name = "DropItemStack", .min_size = 12, .max_size = 12, .compressed = false };
pub const MoveItemStack: PacketInfo = .{ .id = 175, .name = "MoveItemStack", .min_size = 20, .max_size = 20, .compressed = false };
pub const SmartMoveItemStack: PacketInfo = .{ .id = 176, .name = "SmartMoveItemStack", .min_size = 13, .max_size = 13, .compressed = false };
pub const SetActiveSlot: PacketInfo = .{ .id = 177, .name = "SetActiveSlot", .min_size = 8, .max_size = 8, .compressed = false };
pub const SwitchHotbarBlockSet: PacketInfo = .{ .id = 178, .name = "SwitchHotbarBlockSet", .min_size = 1, .max_size = 16384006, .compressed = false };
pub const InventoryAction: PacketInfo = .{ .id = 179, .name = "InventoryAction", .min_size = 6, .max_size = 6, .compressed = false };

// ============================================
// WINDOW PACKETS (200-204)
// ============================================
pub const OpenWindow: PacketInfo = .{ .id = 200, .name = "OpenWindow", .min_size = 6, .max_size = 1677721600, .compressed = true };
pub const UpdateWindow: PacketInfo = .{ .id = 201, .name = "UpdateWindow", .min_size = 5, .max_size = 1677721600, .compressed = true };
pub const CloseWindow: PacketInfo = .{ .id = 202, .name = "CloseWindow", .min_size = 4, .max_size = 4, .compressed = false };
pub const SendWindowAction: PacketInfo = .{ .id = 203, .name = "SendWindowAction", .min_size = 4, .max_size = 32768027, .compressed = false };
pub const ClientOpenWindow: PacketInfo = .{ .id = 204, .name = "ClientOpenWindow", .min_size = 1, .max_size = 1, .compressed = false };

// ============================================
// INTERFACE PACKETS (210-234)
// ============================================
pub const ServerMessage: PacketInfo = .{ .id = 210, .name = "ServerMessage", .min_size = 2, .max_size = 1677721600, .compressed = false };
pub const ChatMessage: PacketInfo = .{ .id = 211, .name = "ChatMessage", .min_size = 1, .max_size = 16384006, .compressed = false };
pub const Notification: PacketInfo = .{ .id = 212, .name = "Notification", .min_size = 2, .max_size = 1677721600, .compressed = false };
pub const KillFeedMessage: PacketInfo = .{ .id = 213, .name = "KillFeedMessage", .min_size = 1, .max_size = 1677721600, .compressed = false };
pub const ShowEventTitle: PacketInfo = .{ .id = 214, .name = "ShowEventTitle", .min_size = 14, .max_size = 1677721600, .compressed = false };
pub const HideEventTitle: PacketInfo = .{ .id = 215, .name = "HideEventTitle", .min_size = 4, .max_size = 4, .compressed = false };
pub const SetPage: PacketInfo = .{ .id = 216, .name = "SetPage", .min_size = 2, .max_size = 2, .compressed = false };
pub const CustomHud: PacketInfo = .{ .id = 217, .name = "CustomHud", .min_size = 2, .max_size = 1677721600, .compressed = true };
pub const CustomPage: PacketInfo = .{ .id = 218, .name = "CustomPage", .min_size = 4, .max_size = 1677721600, .compressed = true };
pub const CustomPageEvent: PacketInfo = .{ .id = 219, .name = "CustomPageEvent", .min_size = 2, .max_size = 16384007, .compressed = false };
pub const EditorBlocksChange: PacketInfo = .{ .id = 222, .name = "EditorBlocksChange", .min_size = 30, .max_size = 139264048, .compressed = true };
pub const ServerInfo: PacketInfo = .{ .id = 223, .name = "ServerInfo", .min_size = 5, .max_size = 32768023, .compressed = false };
pub const AddToServerPlayerList: PacketInfo = .{ .id = 224, .name = "AddToServerPlayerList", .min_size = 1, .max_size = 1677721600, .compressed = false };
pub const RemoveFromServerPlayerList: PacketInfo = .{ .id = 225, .name = "RemoveFromServerPlayerList", .min_size = 1, .max_size = 65536006, .compressed = false };
pub const UpdateServerPlayerList: PacketInfo = .{ .id = 226, .name = "UpdateServerPlayerList", .min_size = 1, .max_size = 131072006, .compressed = false };
pub const UpdateServerPlayerListPing: PacketInfo = .{ .id = 227, .name = "UpdateServerPlayerListPing", .min_size = 1, .max_size = 81920006, .compressed = false };
pub const UpdateKnownRecipes: PacketInfo = .{ .id = 228, .name = "UpdateKnownRecipes", .min_size = 1, .max_size = 1677721600, .compressed = false };
pub const UpdatePortal: PacketInfo = .{ .id = 229, .name = "UpdatePortal", .min_size = 6, .max_size = 16384020, .compressed = false };
pub const UpdateVisibleHudComponents: PacketInfo = .{ .id = 230, .name = "UpdateVisibleHudComponents", .min_size = 1, .max_size = 4096006, .compressed = false };
pub const ResetUserInterfaceState: PacketInfo = .{ .id = 231, .name = "ResetUserInterfaceState", .min_size = 0, .max_size = 0, .compressed = false };
pub const UpdateLanguage: PacketInfo = .{ .id = 232, .name = "UpdateLanguage", .min_size = 1, .max_size = 16384006, .compressed = false };
pub const WorldSavingStatus: PacketInfo = .{ .id = 233, .name = "WorldSavingStatus", .min_size = 1, .max_size = 1, .compressed = false };
pub const OpenChatWithCommand: PacketInfo = .{ .id = 234, .name = "OpenChatWithCommand", .min_size = 1, .max_size = 16384006, .compressed = false };

// ============================================
// WORLDMAP PACKETS (240-245)
// ============================================
pub const UpdateWorldMapSettings: PacketInfo = .{ .id = 240, .name = "UpdateWorldMapSettings", .min_size = 16, .max_size = 1677721600, .compressed = false };
pub const UpdateWorldMap: PacketInfo = .{ .id = 241, .name = "UpdateWorldMap", .min_size = 1, .max_size = 1677721600, .compressed = true };
pub const ClearWorldMap: PacketInfo = .{ .id = 242, .name = "ClearWorldMap", .min_size = 0, .max_size = 0, .compressed = false };
pub const UpdateWorldMapVisible: PacketInfo = .{ .id = 243, .name = "UpdateWorldMapVisible", .min_size = 1, .max_size = 1, .compressed = false };
pub const TeleportToWorldMapMarker: PacketInfo = .{ .id = 244, .name = "TeleportToWorldMapMarker", .min_size = 1, .max_size = 16384006, .compressed = false };
pub const TeleportToWorldMapPosition: PacketInfo = .{ .id = 245, .name = "TeleportToWorldMapPosition", .min_size = 8, .max_size = 8, .compressed = false };

// ============================================
// SERVER ACCESS PACKETS (250-252)
// ============================================
pub const RequestServerAccess: PacketInfo = .{ .id = 250, .name = "RequestServerAccess", .min_size = 3, .max_size = 3, .compressed = false };
pub const UpdateServerAccess: PacketInfo = .{ .id = 251, .name = "UpdateServerAccess", .min_size = 2, .max_size = 1677721600, .compressed = false };
pub const SetServerAccess: PacketInfo = .{ .id = 252, .name = "SetServerAccess", .min_size = 2, .max_size = 16384007, .compressed = false };

// ============================================
// MACHINIMA PACKETS (260-262)
// ============================================
pub const RequestMachinimaActorModel: PacketInfo = .{ .id = 260, .name = "RequestMachinimaActorModel", .min_size = 1, .max_size = 49152028, .compressed = false };
pub const SetMachinimaActorModel: PacketInfo = .{ .id = 261, .name = "SetMachinimaActorModel", .min_size = 1, .max_size = 1677721600, .compressed = false };
pub const UpdateMachinimaScene: PacketInfo = .{ .id = 262, .name = "UpdateMachinimaScene", .min_size = 6, .max_size = 36864033, .compressed = true };

// ============================================
// CAMERA PACKETS (280-283)
// ============================================
pub const SetServerCamera: PacketInfo = .{ .id = 280, .name = "SetServerCamera", .min_size = 157, .max_size = 157, .compressed = false };
pub const CameraShakeEffect: PacketInfo = .{ .id = 281, .name = "CameraShakeEffect", .min_size = 9, .max_size = 9, .compressed = false };
pub const RequestFlyCameraMode: PacketInfo = .{ .id = 282, .name = "RequestFlyCameraMode", .min_size = 1, .max_size = 1, .compressed = false };
pub const SetFlyCameraMode: PacketInfo = .{ .id = 283, .name = "SetFlyCameraMode", .min_size = 1, .max_size = 1, .compressed = false };

// ============================================
// INTERACTION PACKETS (290-294)
// ============================================
pub const SyncInteractionChains: PacketInfo = .{ .id = 290, .name = "SyncInteractionChains", .min_size = 0, .max_size = 1677721600, .compressed = false };
pub const CancelInteractionChain: PacketInfo = .{ .id = 291, .name = "CancelInteractionChain", .min_size = 5, .max_size = 1038, .compressed = false };
pub const PlayInteractionFor: PacketInfo = .{ .id = 292, .name = "PlayInteractionFor", .min_size = 19, .max_size = 16385065, .compressed = false };
pub const MountNPC: PacketInfo = .{ .id = 293, .name = "MountNPC", .min_size = 16, .max_size = 16, .compressed = false };
pub const DismountNPC: PacketInfo = .{ .id = 294, .name = "DismountNPC", .min_size = 0, .max_size = 0, .compressed = false };

// ============================================
// SUN/POST FX (360-361)
// ============================================
pub const UpdateSunSettings: PacketInfo = .{ .id = 360, .name = "UpdateSunSettings", .min_size = 8, .max_size = 8, .compressed = false };
pub const UpdatePostFxSettings: PacketInfo = .{ .id = 361, .name = "UpdatePostFxSettings", .min_size = 20, .max_size = 20, .compressed = false };

// Full packet list for lookup
pub const all_packets = [_]PacketInfo{
    Connect, Disconnect, Ping, Pong,
    Status, AuthGrant, AuthToken, ServerAuthToken, ConnectAccept, PasswordResponse, PasswordAccepted, PasswordRejected, ClientReferral,
    WorldSettings, WorldLoadProgress, WorldLoadFinished, RequestAssets, AssetInitialize, AssetPart, AssetFinalize, RemoveAssets, RequestCommonAssetsRebuild, SetUpdateRate, SetTimeDilation, UpdateFeatures, ViewRadius, PlayerOptions, ServerTags,
    UpdateBlockTypes, UpdateBlockHitboxes, UpdateBlockSoundSets, UpdateItemSoundSets, UpdateBlockParticleSets, UpdateBlockBreakingDecals, UpdateBlockSets, UpdateWeathers, UpdateTrails, UpdateParticleSystems, UpdateParticleSpawners, UpdateEntityEffects, UpdateItemPlayerAnimations, UpdateModelvfxs, UpdateItems, UpdateItemQualities, UpdateItemCategories, UpdateItemReticles, UpdateFieldcraftCategories, UpdateResourceTypes, UpdateRecipes, UpdateEnvironments, UpdateAmbienceFX, UpdateFluidFX, UpdateTranslations, UpdateSoundEvents, UpdateInteractions, UpdateRootInteractions, UpdateUnarmedInteractions, TrackOrUpdateObjective, UntrackObjective, UpdateObjectiveTask, UpdateEntityStatTypes, UpdateEntityUIComponents, UpdateHitboxCollisionConfig, UpdateRepulsionConfig, UpdateViewBobbing, UpdateCameraShake, UpdateBlockGroups, UpdateSoundSets, UpdateAudioCategories, UpdateReverbEffects, UpdateEqualizerEffects, UpdateFluids, UpdateTagPatterns, UpdateProjectileConfigs,
    SetClientId, SetGameMode, SetMovementStates, SetBlockPlacementOverride, JoinWorld, ClientReady, LoadHotbar, SaveHotbar, ClientMovement, ClientTeleport, UpdateMovementSettings, MouseInteraction, DamageInfo, ReticleEvent, DisplayDebug, ClearDebugShapes, SyncPlayerPreferences, ClientPlaceBlock, UpdateMemoriesFeatureStatus, RemoveMapMarker,
    SetChunk, SetChunkHeightmap, SetChunkTintmap, SetChunkEnvironments, UnloadChunk, SetFluids, ServerSetBlock, ServerSetBlocks, ServerSetFluid, ServerSetFluids, UpdateBlockDamage, UpdateTimeSettings, UpdateTime, UpdateEditorTimeOverride, ClearEditorTimeOverride, UpdateWeather, UpdateEditorWeatherOverride, UpdateEnvironmentMusic, SpawnParticleSystem, SpawnBlockParticleSystem, PlaySoundEvent2D, PlaySoundEvent3D, PlaySoundEventEntity, UpdateSleepState, SetPaused, ServerSetPaused,
    SetEntitySeed, EntityUpdates, PlayAnimation, ChangeVelocity, ApplyKnockback, SpawnModelParticles, MountMovement,
    UpdatePlayerInventory, SetCreativeItem, DropCreativeItem, SmartGiveCreativeItem, DropItemStack, MoveItemStack, SmartMoveItemStack, SetActiveSlot, SwitchHotbarBlockSet, InventoryAction,
    OpenWindow, UpdateWindow, CloseWindow, SendWindowAction, ClientOpenWindow,
    ServerMessage, ChatMessage, Notification, KillFeedMessage, ShowEventTitle, HideEventTitle, SetPage, CustomHud, CustomPage, CustomPageEvent, EditorBlocksChange, ServerInfo, AddToServerPlayerList, RemoveFromServerPlayerList, UpdateServerPlayerList, UpdateServerPlayerListPing, UpdateKnownRecipes, UpdatePortal, UpdateVisibleHudComponents, ResetUserInterfaceState, UpdateLanguage, WorldSavingStatus, OpenChatWithCommand,
    UpdateWorldMapSettings, UpdateWorldMap, ClearWorldMap, UpdateWorldMapVisible, TeleportToWorldMapMarker, TeleportToWorldMapPosition,
    RequestServerAccess, UpdateServerAccess, SetServerAccess,
    RequestMachinimaActorModel, SetMachinimaActorModel, UpdateMachinimaScene,
    SetServerCamera, CameraShakeEffect, RequestFlyCameraMode, SetFlyCameraMode,
    SyncInteractionChains, CancelInteractionChain, PlayInteractionFor, MountNPC, DismountNPC,
    UpdateSunSettings, UpdatePostFxSettings,
};

/// Lookup packet by ID
pub fn getById(id: u32) ?PacketInfo {
    for (all_packets) |pkt| {
        if (pkt.id == id) return pkt;
    }
    return null;
}

/// Get packet name by ID (for logging)
pub fn getName(id: u32) []const u8 {
    if (getById(id)) |pkt| {
        return pkt.name;
    }
    return "Unknown";
}

// ============================================
// TESTS
// ============================================

test "lookup known packets" {
    const std = @import("std");

    // Test connection packets
    try std.testing.expectEqual(@as(u32, 0), Connect.id);
    try std.testing.expectEqualStrings("Connect", Connect.name);
    try std.testing.expectEqual(@as(u32, 2), Ping.id);
    try std.testing.expectEqual(@as(u32, 3), Pong.id);

    // Test getById
    const ping = getById(2);
    try std.testing.expect(ping != null);
    try std.testing.expectEqualStrings("Ping", ping.?.name);

    // Test getName
    try std.testing.expectEqualStrings("Ping", getName(2));
    try std.testing.expectEqualStrings("Unknown", getName(9999));

    // Test compressed flag
    try std.testing.expect(!Ping.compressed);
    try std.testing.expect(SetChunk.compressed);
    try std.testing.expect(EntityUpdates.compressed);
}

test "packet size bounds" {
    // Fixed size packets
    try @import("std").testing.expectEqual(Ping.min_size, Ping.max_size);
    try @import("std").testing.expectEqual(@as(u32, 29), Ping.min_size);

    // Variable size packets
    try @import("std").testing.expect(Connect.max_size > Connect.min_size);
    try @import("std").testing.expect(EntityUpdates.max_size > EntityUpdates.min_size);
}

test "all packets have unique IDs" {
    const std = @import("std");
    var seen = std.StaticBitSet(1024).initEmpty();

    for (all_packets) |pkt| {
        if (seen.isSet(pkt.id)) {
            std.debug.print("Duplicate packet ID: {d}\n", .{pkt.id});
            try std.testing.expect(false);
        }
        seen.set(pkt.id);
    }
}
