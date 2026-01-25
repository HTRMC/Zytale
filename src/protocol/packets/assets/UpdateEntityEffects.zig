/// UpdateEntityEffects Packet (ID 50)
///
/// Sends entity effect definitions to the client.
/// Entity effects are status effects that can be applied to entities.

const std = @import("std");
const serializer = @import("serializer.zig");
const entity_effect = @import("../../../assets/types/entity_effect.zig");

pub const EntityEffectAsset = entity_effect.EntityEffectAsset;
pub const OverlapBehavior = entity_effect.OverlapBehavior;
pub const ValueType = entity_effect.ValueType;
pub const StatModifier = entity_effect.StatModifier;

// Constants matching Java UpdateEntityEffects.java
pub const PACKET_ID: u32 = 50;
pub const IS_COMPRESSED: bool = true;
pub const NULLABLE_BIT_FIELD_SIZE: u32 = 1;
pub const FIXED_BLOCK_SIZE: u32 = 25;
pub const VARIABLE_FIELD_COUNT: u32 = 6;
pub const VARIABLE_BLOCK_START: u32 = 49;
pub const MAX_SIZE: u32 = 1677721600;

/// Serialize EntityEffect entry
/// Format from Java (FIXED_BLOCK_SIZE=25, VARIABLE_FIELD_COUNT=6, VARIABLE_BLOCK_START=49):
///
/// FIXED BLOCK (25 bytes):
/// +0:   1 byte  - nullBits
/// +1:   4 bytes - worldRemovalSoundEventIndex (i32 LE)
/// +5:   4 bytes - localRemovalSoundEventIndex (i32 LE)
/// +9:   4 bytes - duration (f32 LE)
/// +13:  1 byte  - infinite (bool)
/// +14:  1 byte  - debuff (bool)
/// +15:  1 byte  - overlapBehavior (enum)
/// +16:  8 bytes - damageCalculatorCooldown (f64 LE)
/// +24:  1 byte  - valueType (enum)
///
/// OFFSET TABLE (24 bytes):
/// +25:  4 bytes - id offset (or -1 if null)
/// +29:  4 bytes - name offset (or -1 if null)
/// +33:  4 bytes - applicationEffects offset (or -1 if null)
/// +37:  4 bytes - modelOverride offset (or -1 if null)
/// +41:  4 bytes - statusEffectIcon offset (or -1 if null)
/// +45:  4 bytes - statModifiers offset (or -1 if null)
///
/// VARIABLE BLOCK (starts at +49)
pub fn serializeEntry(allocator: std.mem.Allocator, entry: *const EntityEffectAsset, writer: *std.ArrayListUnmanaged(u8)) !void {
    const entry_start = writer.items.len;

    // Calculate nullBits
    var null_bits: u8 = 0;
    if (entry.id.len > 0) null_bits |= 0x01; // bit 0 = id
    if (entry.name != null) null_bits |= 0x02; // bit 1 = name
    // bit 2 = applicationEffects (not implemented, always null)
    // bit 3 = modelOverride (not implemented, always null)
    if (entry.status_effect_icon != null) null_bits |= 0x10; // bit 4 = statusEffectIcon
    if (entry.stat_modifiers != null and entry.stat_modifiers.?.len > 0) null_bits |= 0x20; // bit 5 = statModifiers

    try writer.append(allocator, null_bits);

    // worldRemovalSoundEventIndex (i32 LE)
    try serializer.writeI32(allocator, writer, entry.world_removal_sound_index);

    // localRemovalSoundEventIndex (i32 LE)
    try serializer.writeI32(allocator, writer, entry.local_removal_sound_index);

    // duration (f32 LE)
    try serializer.writeF32(allocator, writer, entry.duration);

    // infinite (bool)
    try writer.append(allocator, if (entry.infinite) @as(u8, 1) else @as(u8, 0));

    // debuff (bool)
    try writer.append(allocator, if (entry.debuff) @as(u8, 1) else @as(u8, 0));

    // overlapBehavior (enum u8)
    try writer.append(allocator, @intFromEnum(entry.overlap_behavior));

    // damageCalculatorCooldown (f64 LE)
    try serializer.writeF64(allocator, writer, entry.damage_calculator_cooldown);

    // valueType (enum u8)
    try writer.append(allocator, @intFromEnum(entry.value_type));

    // OFFSET TABLE (6 offsets x 4 bytes = 24 bytes)
    const id_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4); // id offset placeholder

    const name_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4); // name offset placeholder

    const app_effects_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4); // applicationEffects offset placeholder

    const model_override_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4); // modelOverride offset placeholder

    const status_icon_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4); // statusEffectIcon offset placeholder

    const stat_mods_offset_pos = writer.items.len;
    try writer.appendNTimes(allocator, 0, 4); // statModifiers offset placeholder

    // Variable block starts at offset 49 from entry_start
    const var_block_start = entry_start + 49;

    // id VarString (if present)
    if (entry.id.len > 0) {
        const id_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[id_offset_pos..][0..4], id_offset, .little);
        try serializer.writeVarString(allocator, writer, entry.id);
    } else {
        std.mem.writeInt(i32, writer.items[id_offset_pos..][0..4], -1, .little);
    }

    // name VarString (if present)
    if (entry.name) |name| {
        const name_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[name_offset_pos..][0..4], name_offset, .little);
        try serializer.writeVarString(allocator, writer, name);
    } else {
        std.mem.writeInt(i32, writer.items[name_offset_pos..][0..4], -1, .little);
    }

    // applicationEffects (not implemented, always null/-1)
    std.mem.writeInt(i32, writer.items[app_effects_offset_pos..][0..4], -1, .little);

    // modelOverride (not implemented, always null/-1)
    std.mem.writeInt(i32, writer.items[model_override_offset_pos..][0..4], -1, .little);

    // statusEffectIcon VarString (if present)
    if (entry.status_effect_icon) |icon| {
        const icon_offset: i32 = @intCast(writer.items.len - var_block_start);
        std.mem.writeInt(i32, writer.items[status_icon_offset_pos..][0..4], icon_offset, .little);
        try serializer.writeVarString(allocator, writer, icon);
    } else {
        std.mem.writeInt(i32, writer.items[status_icon_offset_pos..][0..4], -1, .little);
    }

    // statModifiers Map<Integer, Float> (if present)
    if (entry.stat_modifiers) |mods| {
        if (mods.len > 0) {
            const mods_offset: i32 = @intCast(writer.items.len - var_block_start);
            std.mem.writeInt(i32, writer.items[stat_mods_offset_pos..][0..4], mods_offset, .little);

            // Write VarInt count
            var count_buf: [5]u8 = undefined;
            const count_len = serializer.writeVarInt(&count_buf, @intCast(mods.len));
            try writer.appendSlice(allocator, count_buf[0..count_len]);

            // Write each entry: key (i32 LE) + value (f32 LE)
            for (mods) |mod| {
                try serializer.writeI32(allocator, writer, mod.key);
                try serializer.writeF32(allocator, writer, mod.value);
            }
        } else {
            std.mem.writeInt(i32, writer.items[stat_mods_offset_pos..][0..4], -1, .little);
        }
    } else {
        std.mem.writeInt(i32, writer.items[stat_mods_offset_pos..][0..4], -1, .little);
    }
}

/// Serialize full packet with entries
pub fn serialize(
    allocator: std.mem.Allocator,
    update_type: serializer.UpdateType,
    max_id: i32,
    entries: []const serializer.AssetSerializer(EntityEffectAsset).IndexedEntry,
) ![]u8 {
    return serializer.AssetSerializer(EntityEffectAsset).serialize(
        allocator,
        update_type,
        max_id,
        entries,
        &[_]u8{},
        serializeEntry,
    );
}

/// Build empty packet (7 bytes)
/// Format: nullBits(1) + type(1) + maxId(4) + VarInt(0)
pub fn buildEmptyPacket(allocator: std.mem.Allocator) ![]u8 {
    return serializer.serializeEmptyUpdate(allocator, .init, 0, &[_]u8{});
}

// ============================================================================
// Tests
// ============================================================================

test "UpdateEntityEffects empty packet size" {
    const allocator = std.testing.allocator;

    const pkt = try buildEmptyPacket(allocator);
    defer allocator.free(pkt);

    // FIXED=6: nullBits(1) + type(1) + maxId(4) + VarInt 0(1) = 7 bytes
    try std.testing.expectEqual(@as(usize, 7), pkt.len);
    try std.testing.expectEqual(@as(u8, 0x01), pkt[0]); // nullBits
    try std.testing.expectEqual(@as(u8, 0x00), pkt[1]); // type
    try std.testing.expectEqual(@as(i32, 0), std.mem.readInt(i32, pkt[2..6], .little)); // maxId
    try std.testing.expectEqual(@as(u8, 0x00), pkt[6]); // VarInt count = 0
}
