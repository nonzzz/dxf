const std = @import("std");

pub fn build(b: *std.Build) void {
    const build_steps = .{
        .test_unit = b.step("test:unit", "Run unit tests"),
    };

    const mod = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const target = b.standardTargetOptions(.{});

    build_test_unit(b, build_steps.test_unit, .{
        .mode = mod,
        .target = target,
    });
}

fn build_test_unit(b: *std.Build, step_test_unit: *std.Build.Step, options: struct {
    mode: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
}) void {
    const tokenizer_mod = b.createModule(.{
        .root_source_file = b.path("src/tokenizer/lib.zig"),
        .target = options.target,
        .optimize = options.mode,
    });

    const parse_mod = b.createModule(.{
        .root_source_file = b.path("src/parse/lib.zig"),
        .target = options.target,
        .optimize = options.mode,
    });

    parse_mod.addImport("tokenizer", tokenizer_mod);

    const tokenizer_tests = b.addTest(.{
        .name = "test-tokenizer",
        .root_module = tokenizer_mod,
    });

    const parse_tests = b.addTest(.{
        .name = "test-parse",
        .root_module = parse_mod,
    });

    const unit_tests = b.addTest(.{
        .name = "test-dxf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/unit_tests.zig"),
            .target = options.target,
            .optimize = options.mode,
        }),
    });
    unit_tests.root_module.addImport("tokenizer", tokenizer_mod);
    unit_tests.root_module.addImport("parse", parse_mod);

    const run_tokenizer_tests = b.addRunArtifact(tokenizer_tests);
    const run_parse_tests = b.addRunArtifact(parse_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    step_test_unit.dependOn(&run_tokenizer_tests.step);
    step_test_unit.dependOn(&run_parse_tests.step);
    step_test_unit.dependOn(&run_unit_tests.step);
}
