const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Protocol module (shared)
    const protocol_module = b.createModule(.{
        .root_source_file = b.path("src/protocol/registry.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main proxy/server executable
    const exe = b.addExecutable(.{
        .name = "zytale",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "protocol", .module = protocol_module },
            },
        }),
    });

    // Link Windows libraries for QUIC and crypto
    if (target.result.os.tag == .windows) {
        exe.root_module.linkSystemLibrary("ws2_32", .{});
        exe.root_module.linkSystemLibrary("crypt32", .{});
        exe.root_module.linkSystemLibrary("ncrypt", .{});
    }

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the proxy/server");
    run_step.dependOn(&run_cmd.step);

    // List packets tool
    const list_packets_module = b.createModule(.{
        .root_source_file = b.path("src/tools/list_packets.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protocol", .module = protocol_module },
        },
    });

    const list_packets = b.addExecutable(.{
        .name = "list-packets",
        .root_module = list_packets_module,
    });

    b.installArtifact(list_packets);

    const list_packets_cmd = b.addRunArtifact(list_packets);
    const list_packets_step = b.step("list-packets", "List all known Hytale packets");
    list_packets_step.dependOn(&list_packets_cmd.step);

    // Unit tests - test standalone modules that don't have relative imports
    const test_modules = [_][]const u8{
        "src/protocol/registry.zig",
        "src/net/packet/varint.zig",
        "src/net/packet/frame.zig",
        "src/world/constants.zig",
        "src/net/compression/zstd.zig",
    };

    const test_step = b.step("test", "Run unit tests");

    for (test_modules) |test_path| {
        const unit_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_path),
                .target = target,
                .optimize = optimize,
            }),
        });

        const run_test = b.addRunArtifact(unit_test);
        test_step.dependOn(&run_test.step);
    }

    // Assets module tests (includes packet.zig with serializer tests)
    // Note: packet.zig imports serializer from protocol, so we need to inline those functions
    // or test through main. For now, we test through the main module.
    const main_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "protocol", .module = protocol_module },
            },
        }),
    });

    if (target.result.os.tag == .windows) {
        main_test.root_module.linkSystemLibrary("ws2_32", .{});
        main_test.root_module.linkSystemLibrary("crypt32", .{});
        main_test.root_module.linkSystemLibrary("ncrypt", .{});
    }

    const run_main_test = b.addRunArtifact(main_test);
    test_step.dependOn(&run_main_test.step);
}
