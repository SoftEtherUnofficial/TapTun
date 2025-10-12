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

    // Create main module with iOS SDK paths if needed
    const main_module = b.createModule(.{
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add iOS SDK include paths for @cImport
    if (ios_sdk_path) |sdk| {
        const ios_include = b.fmt("{s}/usr/include", .{sdk});
        main_module.addSystemIncludePath(.{ .cwd_relative = ios_include });
    }

    // Main library module (for future examples/consumers)
    _ = b.addModule("taptun", main_module);

    // Static library (for C interop)
    const lib = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = main_module,
        .kind = .lib,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Shared library
    const shared_lib = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = main_module,
        .kind = .lib,
        .linkage = .dynamic,
    });
    b.installArtifact(shared_lib);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = main_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Documentation
    const docs = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = main_module,
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
}
