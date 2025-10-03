const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library module (for future examples/consumers)
    _ = b.addModule("taptun", .{
        .root_source_file = b.path("src/taptun.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library (for C interop)
    const lib = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/taptun.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .kind = .lib,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Shared library
    const shared_lib = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/taptun.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .kind = .lib,
        .linkage = .dynamic,
    });
    b.installArtifact(shared_lib);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/taptun.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Documentation
    const docs = std.Build.Step.Compile.create(b, .{
        .name = "taptun",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/taptun.zig"),
            .target = target,
            .optimize = .Debug,
        }),
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
