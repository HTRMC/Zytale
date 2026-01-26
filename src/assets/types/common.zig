/// Common types for the asset system
/// Matches the Java protocol definitions

const std = @import("std");

/// UpdateType enum (matches Java UpdateType)
/// Used in all Update* packets to indicate the type of update
pub const UpdateType = enum(u8) {
    /// Initial load - send all assets
    init = 0,
    /// Add or update specific assets
    add_or_update = 1,
    /// Remove assets
    remove = 2,

    pub fn fromValue(value: u8) !UpdateType {
        return switch (value) {
            0 => .init,
            1 => .add_or_update,
            2 => .remove,
            else => error.InvalidUpdateType,
        };
    }
};

/// Color type for asset serialization (RGB, 3 bytes)
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const WHITE: Color = .{ .r = 255, .g = 255, .b = 255 };
    pub const BLACK: Color = .{ .r = 0, .g = 0, .b = 0 };

    /// Parse hex color string "#RRGGBB" or "RRGGBB"
    pub fn fromHex(hex: []const u8) ?Color {
        var start: usize = 0;
        if (hex.len > 0 and hex[0] == '#') start = 1;

        const slice = hex[start..];
        if (slice.len != 6) return null;

        const r = std.fmt.parseInt(u8, slice[0..2], 16) catch return null;
        const g = std.fmt.parseInt(u8, slice[2..4], 16) catch return null;
        const b = std.fmt.parseInt(u8, slice[4..6], 16) catch return null;

        return .{ .r = r, .g = g, .b = b };
    }

    /// Serialize to buffer (3 bytes)
    pub fn serialize(self: Color, buf: []u8) void {
        buf[0] = self.r;
        buf[1] = self.g;
        buf[2] = self.b;
    }
};

/// ColorAlpha type (RGBA, 4 bytes)
pub const ColorAlpha = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn fromColor(color: Color, alpha: u8) ColorAlpha {
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = alpha };
    }

    pub fn serialize(self: ColorAlpha, buf: []u8) void {
        buf[0] = self.r;
        buf[1] = self.g;
        buf[2] = self.b;
        buf[3] = self.a;
    }
};

/// Asset type identifiers - matches the packet IDs
pub const AssetType = enum(u8) {
    block_types = 40,
    block_hitboxes = 41,
    block_sound_sets = 42,
    item_sound_sets = 43,
    block_particle_sets = 44,
    block_breaking_decals = 45,
    block_sets = 46,
    weathers = 47,
    trails = 48,
    particle_systems = 49,
    particle_spawners = 50,
    entity_effects = 51,
    item_player_animations = 52,
    model_vfxs = 53,
    items = 54,
    item_qualities = 55,
    item_categories = 56,
    item_reticles = 57,
    fieldcraft_categories = 58,
    resource_types = 59,
    recipes = 60,
    environments = 61,
    ambience_fx = 62,
    fluid_fx = 63,
    translations = 64,
    sound_events = 65,
    interactions = 66,
    root_interactions = 67,
    unarmed_interactions = 68,
    entity_stat_types = 72,
    entity_ui_components = 73,
    hitbox_collision_config = 74,
    repulsion_config = 75,
    view_bobbing = 76,
    camera_shake = 77,
    block_groups = 78,
    sound_sets = 79,
    audio_categories = 80,
    reverb_effects = 81,
    equalizer_effects = 82,
    fluids = 83,
    tag_patterns = 84,
    projectile_configs = 85,

    pub fn getPacketId(self: AssetType) u32 {
        return @intFromEnum(self);
    }

    pub fn getName(self: AssetType) []const u8 {
        return switch (self) {
            .block_types => "BlockTypes",
            .block_hitboxes => "BlockHitboxes",
            .block_sound_sets => "BlockSoundSets",
            .item_sound_sets => "ItemSoundSets",
            .block_particle_sets => "BlockParticleSets",
            .block_breaking_decals => "BlockBreakingDecals",
            .block_sets => "BlockSets",
            .weathers => "Weathers",
            .trails => "Trails",
            .particle_systems => "ParticleSystems",
            .particle_spawners => "ParticleSpawners",
            .entity_effects => "EntityEffects",
            .item_player_animations => "ItemPlayerAnimations",
            .model_vfxs => "ModelVFXs",
            .items => "Items",
            .item_qualities => "ItemQualities",
            .item_categories => "ItemCategories",
            .item_reticles => "ItemReticles",
            .fieldcraft_categories => "FieldcraftCategories",
            .resource_types => "ResourceTypes",
            .recipes => "Recipes",
            .environments => "Environments",
            .ambience_fx => "AmbienceFX",
            .fluid_fx => "FluidFX",
            .translations => "Translations",
            .sound_events => "SoundEvents",
            .interactions => "Interactions",
            .root_interactions => "RootInteractions",
            .unarmed_interactions => "UnarmedInteractions",
            .entity_stat_types => "EntityStatTypes",
            .entity_ui_components => "EntityUIComponents",
            .hitbox_collision_config => "HitboxCollisionConfig",
            .repulsion_config => "RepulsionConfig",
            .view_bobbing => "ViewBobbing",
            .camera_shake => "CameraShake",
            .block_groups => "BlockGroups",
            .sound_sets => "SoundSets",
            .audio_categories => "AudioCategories",
            .reverb_effects => "ReverbEffects",
            .equalizer_effects => "EqualizerEffects",
            .fluids => "Fluids",
            .tag_patterns => "TagPatterns",
            .projectile_configs => "ProjectileConfigs",
        };
    }
};

/// ZIP paths for each asset type
pub fn getZipPath(asset_type: AssetType) []const u8 {
    return switch (asset_type) {
        .ambience_fx => "Server/Audio/AmbienceFX/",
        .audio_categories => "Server/Audio/AudioCategories/",
        .block_breaking_decals => "Server/Item/Block/BreakingDecals/",
        .block_hitboxes => "Server/Item/Block/Hitboxes/",
        .block_particle_sets => "Server/Particles/BlockParticleSets/",
        .block_sets => "Server/Item/Block/BlockSets/",
        .block_sound_sets => "Server/Audio/BlockSounds/",
        .block_types => "Server/Item/Block/Blocks/",
        .entity_effects => "Server/Entity/Effects/",
        .entity_stat_types => "Server/Entity/StatTypes/",
        .entity_ui_components => "Server/Entity/UIComponents/",
        .environments => "Server/Environments/",
        .equalizer_effects => "Server/Audio/EqualizerEffects/",
        .fieldcraft_categories => "Server/Item/FieldcraftCategories/",
        .fluid_fx => "Server/Item/Block/FluidFX/",
        .fluids => "Server/Item/Block/Fluids/",
        .hitbox_collision_config => "Server/GameplayConfigs/",
        .interactions => "Server/Item/Interactions/",
        .item_player_animations => "Server/Item/Animations/",
        .item_categories => "Server/Item/Categories/",
        .item_qualities => "Server/Item/Quality/",
        .item_reticles => "Server/Item/Reticles/",
        .items => "Server/Item/Items/",
        .item_sound_sets => "Server/Audio/ItemSounds/",
        .model_vfxs => "Server/Models/VFX/",
        .particle_spawners => "Server/Particles/Spawners/",
        .particle_systems => "Server/Particles/Systems/",
        .recipes => "Server/Item/Recipes/",
        .repulsion_config => "Server/GameplayConfigs/",
        .resource_types => "Server/Item/ResourceTypes/",
        .reverb_effects => "Server/Audio/Reverb/",
        .root_interactions => "Server/Item/RootInteractions/",
        .sound_events => "Server/Audio/SoundEvents/",
        .sound_sets => "Server/Audio/SoundSets/",
        .tag_patterns => "Server/TagPatterns/",
        .trails => "Server/Entity/Trails/",
        .translations => "Server/Languages/",
        .unarmed_interactions => "Server/Item/Unarmed/",
        .weathers => "Server/Weathers/",
        .view_bobbing => "Server/GameplayConfigs/",
        .camera_shake => "Server/GameplayConfigs/",
        .block_groups => "Server/Item/Block/Groups/",
        .projectile_configs => "Server/Projectiles/",
    };
}

test "UpdateType roundtrip" {
    try std.testing.expectEqual(UpdateType.init, try UpdateType.fromValue(0));
    try std.testing.expectEqual(UpdateType.add_or_update, try UpdateType.fromValue(1));
    try std.testing.expectEqual(UpdateType.remove, try UpdateType.fromValue(2));
}

test "Color from hex" {
    const white = Color.fromHex("#FFFFFF").?;
    try std.testing.expectEqual(@as(u8, 255), white.r);
    try std.testing.expectEqual(@as(u8, 255), white.g);
    try std.testing.expectEqual(@as(u8, 255), white.b);

    const red = Color.fromHex("FF0000").?;
    try std.testing.expectEqual(@as(u8, 255), red.r);
    try std.testing.expectEqual(@as(u8, 0), red.g);
    try std.testing.expectEqual(@as(u8, 0), red.b);
}

/// Vector2f type (8 bytes)
pub const Vector2f = struct {
    x: f32,
    y: f32,

    pub const ZERO: Vector2f = .{ .x = 0.0, .y = 0.0 };
    pub const ONE: Vector2f = .{ .x = 1.0, .y = 1.0 };

    /// Serialize to buffer (8 bytes, little endian)
    pub fn serialize(self: Vector2f, buf: []u8) void {
        std.mem.writeInt(u32, buf[0..4], @bitCast(self.x), .little);
        std.mem.writeInt(u32, buf[4..8], @bitCast(self.y), .little);
    }
};

test "Vector2f serialization" {
    var buf: [8]u8 = undefined;
    const v = Vector2f{ .x = 1.0, .y = 2.0 };
    v.serialize(&buf);

    const x: f32 = @bitCast(std.mem.readInt(u32, buf[0..4], .little));
    const y: f32 = @bitCast(std.mem.readInt(u32, buf[4..8], .little));
    try std.testing.expectEqual(@as(f32, 1.0), x);
    try std.testing.expectEqual(@as(f32, 2.0), y);
}
