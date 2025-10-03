const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library module
    const taptun_mod = b.addModule("taptun", .{
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library (for C interop)
    const lib = b.addStaticLibrary(.{
        .name = "taptun",
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Shared library
    const shared_lib = b.addSharedLibrary(.{
        .name = "taptun",
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(shared_lib);

    // Example executables
    const examples = [_]struct { name: []const u8, src: []const u8, desc: []const u8 }{
        .{ .name = "simple-tun", .src = "examples/simple_tun.zig", .desc = "Basic TUN device example" },
        .{ .name = "simple-tap", .src = "examples/simple_tap.zig", .desc = "Basic TAP device example" },
        .{ .name = "vpn-client", .src = "examples/vpn_client.zig", .desc = "VPN client with L2↔L3 translation" },
        .{ .name = "l2l3-test", .src = "examples/l2l3_translator.zig", .desc = "L2↔L3 translator test" },
    };

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(example.src),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("taptun", taptun_mod);

        const install_exe = b.addInstallArtifact(exe, .{});
        const example_step = b.step(example.name, example.desc);
        example_step.dependOn(&install_exe.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install_exe.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step(b.fmt("run-{s}", .{example.name}), b.fmt("Run {s}", .{example.desc}));
        run_step.dependOn(&run_cmd.step);
    }

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests (require root privileges)
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("taptun", taptun_mod);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests (requires root/sudo)");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Platform-specific tests
    const platform_tests = b.addTest(.{
        .root_source_file = b.path("tests/platform.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform_tests.root_module.addImport("taptun", taptun_mod);

    const run_platform_tests = b.addRunArtifact(platform_tests);
    const platform_test_step = b.step("test-platform", "Run platform-specific tests");
    platform_test_step.dependOn(&run_platform_tests.step);

    // Documentation
    const docs = b.addStaticLibrary(.{
        .name = "taptun",
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = .Debug,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("bench/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench.root_module.addImport("taptun", taptun_mod);

    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);
}
