const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Check if building for iOS
    const is_ios = target.result.os.tag == .ios;

    // Determine iOS SDK path if needed
    const ios_sdk_path = if (is_ios) blk: {
        if (target.result.cpu.arch == .aarch64 and target.result.abi == .simulator) {
            break :blk "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk";
        } else if (target.result.cpu.arch == .x86_64) {
            break :blk "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk";
        } else {
            break :blk "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk";
        }
    } else null;

    // Export module (works with both Zig 0.13 and 0.15)
    const taptun_module = b.addModule("taptun", .{
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add iOS SDK include paths for @cImport
    if (ios_sdk_path) |sdk| {
        const ios_include = b.fmt("{s}/usr/include", .{sdk});
        taptun_module.addSystemIncludePath(.{ .cwd_relative = ios_include });
    }

    // Create libraries using Zig 0.15 API (compatible with module system)
    // Note: This uses Step.Compile.create which works with main_module
    const lib = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = taptun_module,
        .kind = .lib,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const shared_lib = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = taptun_module,
        .kind = .lib,
        .linkage = .dynamic,
    });
    b.installArtifact(shared_lib);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = taptun_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Documentation
    const docs = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = taptun_module,
        .kind = .lib,
        .linkage = .static,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    // Benchmark executables
    const throughput_module = b.createModule(.{
        .root_source_file = b.path("bench/throughput.zig"),
        .target = target,
        .optimize = optimize,
    });
    throughput_module.addImport("taptun", taptun_module);

    const throughput_exe = std.Build.Step.Compile.create(b, .{
        .name = "throughput",
        .root_module = throughput_module,
        .kind = .exe,
        .linkage = null,
    });

    const latency_module = b.createModule(.{
        .root_source_file = b.path("bench/latency.zig"),
        .target = target,
        .optimize = optimize,
    });
    latency_module.addImport("taptun", taptun_module);

    const latency_exe = std.Build.Step.Compile.create(b, .{
        .name = "latency",
        .root_module = latency_module,
        .kind = .exe,
        .linkage = null,
    });

    const install_throughput = b.addInstallArtifact(throughput_exe, .{});
    const install_latency = b.addInstallArtifact(latency_exe, .{});

    const bench_step = b.step("bench", "Build benchmarks");
    bench_step.dependOn(&install_throughput.step);
    bench_step.dependOn(&install_latency.step);

    const run_throughput = b.addRunArtifact(throughput_exe);
    const run_latency = b.addRunArtifact(latency_exe);

    const run_bench_step = b.step("run-bench", "Run all benchmarks");
    run_bench_step.dependOn(&run_throughput.step);
    run_bench_step.dependOn(&run_latency.step);
}
