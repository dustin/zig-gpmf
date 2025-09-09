const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const zeit = b.dependency("zeit", .{
        .target = target,
        .optimize = optimize,
    });
    const marble = b.dependency("marble", .{
        .target = target,
        .optimize = optimize,
    });
    const zigthesis = b.dependency("zigthesis", .{
        .target = target,
        .optimize = optimize,
    });

    const gpmf = b.addModule("gpmf", .{
        .root_source_file = b.path("src/gpmf.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zeit", .module = zeit.module("zeit") },
            .{ .name = "marble", .module = marble.module("marble") },
            .{ .name = "zigthesis", .module = zigthesis.module("zigthesis") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zig-gpmf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gpmf", .module = gpmf },
                .{ .name = "zeit", .module = zeit.module("zeit") },
            },
        }),
    });

    b.installArtifact(exe);

    const kmlexe = b.addExecutable(.{
        .name = "gpmf-to-kml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gpmf-to-kml.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gpmf", .module = gpmf },
                .{ .name = "zeit", .module = zeit.module("zeit") },
            },
        }),
    });
    kmlexe.root_module.addImport("gpmf", gpmf);

    b.installArtifact(kmlexe);

    const unit_tests = b.addTest(.{ .root_module = gpmf });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    {
        const docs_step = b.step("docs", "Build the Telemetry Stream docs");
        const docs_obj = b.addObject(.{
            .name = "gpmf",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tstream.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const docs = docs_obj.getEmittedDocs();
        docs_step.dependOn(&b.addInstallDirectory(.{
            .source_dir = docs,
            .install_dir = .prefix,
            .install_subdir = "docs",
        }).step);
    }
}
