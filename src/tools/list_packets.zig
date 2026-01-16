const std = @import("std");
const registry = @import("protocol");

pub fn main() void {
    const print = std.debug.print;

    print("\n", .{});
    print("+----------------------------------------------------------------------+\n", .{});
    print("|               Hytale Protocol - Packet Registry                      |\n", .{});
    print("+-------+-------------------------------+-------------+----------------+\n", .{});
    print("|  ID   | Name                          | Size        | Compressed     |\n", .{});
    print("+-------+-------------------------------+-------------+----------------+\n", .{});

    var count: usize = 0;
    for (registry.all_packets) |pkt| {
        const compressed_str = if (pkt.compressed) "Yes" else "No ";

        if (pkt.min_size == pkt.max_size) {
            print("| {d:>4}  | {s:<29} | {d:>5} fixed | {s:<14} |\n", .{
                pkt.id,
                pkt.name,
                pkt.min_size,
                compressed_str,
            });
        } else {
            print("| {d:>4}  | {s:<29} | {d:>5}-{d:<5} | {s:<14} |\n", .{
                pkt.id,
                pkt.name,
                pkt.min_size,
                @min(pkt.max_size, 99999),
                compressed_str,
            });
        }
        count += 1;
    }

    print("+-------+-------------------------------+-------------+----------------+\n", .{});
    print("\nTotal packets: {d}\n\n", .{count});

    // Print some stats
    var compressed_count: usize = 0;
    var fixed_size_count: usize = 0;
    for (registry.all_packets) |pkt| {
        if (pkt.compressed) compressed_count += 1;
        if (pkt.min_size == pkt.max_size) fixed_size_count += 1;
    }

    print("Stats:\n", .{});
    print("  - Compressed packets: {d}\n", .{compressed_count});
    print("  - Fixed-size packets: {d}\n", .{fixed_size_count});
    print("  - Variable-size packets: {d}\n", .{count - fixed_size_count});
}
