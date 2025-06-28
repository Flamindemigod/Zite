const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/Zite.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addCSourceFile(.{ .file = b.path("sqlite/sqlite3.c") });
    lib_mod.addIncludePath(b.path("sqlite"));
    lib_mod.link_libc = true;

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Zite",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    const pubMod = b.addModule("Zite", .{
        .root_source_file = b.path("src/Zite.zig"),
        .link_libc = true,
    });
    pubMod.addCSourceFile(.{ .file = b.path("sqlite/sqlite3.c") });
    pubMod.addIncludePath(b.path("sqlite"));
}
