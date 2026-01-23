/// IndexedAssetMap - Maps string keys to assets with integer indices for network serialization
///
/// When assets are sent over the network, they're identified by integer indices rather than
/// string keys. This map maintains the string → index mapping and provides access to assets
/// by either their string key or integer index.

const std = @import("std");

/// Generic IndexedAssetMap that maps string keys to values with auto-assigned indices
pub fn IndexedAssetMap(comptime V: type) type {
    return struct {
        allocator: std.mem.Allocator,

        /// Assets stored by their string key
        assets: std.StringHashMap(Entry),

        /// Index to key mapping for reverse lookup
        index_to_key: std.AutoHashMap(u32, []const u8),

        /// Next available index
        next_index: u32,

        const Self = @This();

        pub const Entry = struct {
            index: u32,
            value: V,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .assets = std.StringHashMap(Entry).init(allocator),
                .index_to_key = std.AutoHashMap(u32, []const u8).init(allocator),
                .next_index = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            // Free allocated keys
            var iter = self.assets.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.assets.deinit();
            self.index_to_key.deinit();
        }

        /// Add or update an asset by key
        /// Returns the assigned index
        pub fn put(self: *Self, key: []const u8, value: V) !u32 {
            // Check if key already exists
            if (self.assets.getPtr(key)) |existing| {
                // Update existing entry (keep same index)
                existing.value = value;
                return existing.index;
            }

            // Allocate new key
            const owned_key = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(owned_key);

            const index = self.next_index;
            self.next_index += 1;

            try self.assets.put(owned_key, .{ .index = index, .value = value });
            try self.index_to_key.put(index, owned_key);

            return index;
        }

        /// Get asset by string key
        pub fn getByKey(self: *const Self, key: []const u8) ?*const Entry {
            if (self.assets.getPtr(key)) |entry| {
                return entry;
            }
            return null;
        }

        /// Get asset by index
        pub fn getByIndex(self: *const Self, index: u32) ?*const Entry {
            if (self.index_to_key.get(index)) |key| {
                return self.assets.getPtr(key);
            }
            return null;
        }

        /// Get the index for a key
        pub fn getIndex(self: *const Self, key: []const u8) ?u32 {
            if (self.assets.get(key)) |entry| {
                return entry.index;
            }
            return null;
        }

        /// Get total count of assets
        pub fn count(self: *const Self) usize {
            return self.assets.count();
        }

        /// Get the max ID (next_index value) - needed for packet serialization
        pub fn maxId(self: *const Self) u32 {
            return self.next_index;
        }

        /// Iterator over all entries
        pub const Iterator = struct {
            inner: std.StringHashMap(Entry).Iterator,

            pub fn next(self: *Iterator) ?struct { key: []const u8, index: u32, value: *V } {
                if (self.inner.next()) |entry| {
                    return .{
                        .key = entry.key_ptr.*,
                        .index = entry.value_ptr.index,
                        .value = &entry.value_ptr.value,
                    };
                }
                return null;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return .{ .inner = self.assets.iterator() };
        }

        /// Const iterator over all entries
        pub const ConstIterator = struct {
            inner: std.StringHashMap(Entry).Iterator,

            pub fn next(self: *ConstIterator) ?struct { key: []const u8, index: u32, value: V } {
                if (self.inner.next()) |entry| {
                    return .{
                        .key = entry.key_ptr.*,
                        .index = entry.value_ptr.index,
                        .value = entry.value_ptr.value,
                    };
                }
                return null;
            }
        };

        pub fn constIterator(self: *const Self) ConstIterator {
            // Need a mutable reference to get the iterator from HashMap
            const mutable_ptr: *Self = @constCast(self);
            return .{ .inner = mutable_ptr.assets.iterator() };
        }
    };
}

test "IndexedAssetMap basic operations" {
    const allocator = std.testing.allocator;

    var map = IndexedAssetMap(i32).init(allocator);
    defer map.deinit();

    // Add entries
    const idx1 = try map.put("foo", 100);
    const idx2 = try map.put("bar", 200);
    const idx3 = try map.put("baz", 300);

    // Indices should be sequential
    try std.testing.expectEqual(@as(u32, 0), idx1);
    try std.testing.expectEqual(@as(u32, 1), idx2);
    try std.testing.expectEqual(@as(u32, 2), idx3);

    // Lookup by key
    try std.testing.expectEqual(@as(i32, 100), map.getByKey("foo").?.value);
    try std.testing.expectEqual(@as(i32, 200), map.getByKey("bar").?.value);
    try std.testing.expectEqual(@as(i32, 300), map.getByKey("baz").?.value);

    // Lookup by index
    try std.testing.expectEqual(@as(i32, 100), map.getByIndex(0).?.value);
    try std.testing.expectEqual(@as(i32, 200), map.getByIndex(1).?.value);
    try std.testing.expectEqual(@as(i32, 300), map.getByIndex(2).?.value);

    // Count and maxId
    try std.testing.expectEqual(@as(usize, 3), map.count());
    try std.testing.expectEqual(@as(u32, 3), map.maxId());
}

test "IndexedAssetMap update existing" {
    const allocator = std.testing.allocator;

    var map = IndexedAssetMap(i32).init(allocator);
    defer map.deinit();

    const idx1 = try map.put("foo", 100);
    try std.testing.expectEqual(@as(u32, 0), idx1);
    try std.testing.expectEqual(@as(i32, 100), map.getByKey("foo").?.value);

    // Update existing key - should keep same index
    const idx2 = try map.put("foo", 999);
    try std.testing.expectEqual(@as(u32, 0), idx2); // Same index

    // Count should still be 1
    try std.testing.expectEqual(@as(usize, 1), map.count());
}
