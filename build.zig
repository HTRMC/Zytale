const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main proxy executable
    const exe = b.addExecutable(.{
        .name = "zytale",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the proxy");
    run_step.dependOn(&run_cmd.step);

    // List packets tool
    const protocol_module = b.createModule(.{
        .root_source_file = b.path("src/protocol/registry.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/protocol/registry.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
