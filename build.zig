const std = @import("std");

pub fn build(b: *std.Build) !void {
    const request_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // minimum supported version is Windows 10 RS5
    const target = if (request_target.result.os.tag == .windows)
        b.resolveTargetQuery(.{
            .os_tag = .windows,
            .os_version_min = .{ .windows = .win10_rs5 },
            .abi = .gnu,
            .cpu_arch = request_target.result.cpu.arch,
        })
    else
        request_target;

    const config = b.addOptions();
    const version = try Version.init(b);
    config.addOption(std.SemanticVersion, "version", version.version);

    const toml_dep = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });
    const toml_mod = toml_dep.module("zig-toml");

    const gitz_dep = b.dependency("gitz", .{
        .target = target,
        .optimize = optimize,
    });
    const gitz_mod = gitz_dep.module("gitz");

    const clap = b.dependency("clap", .{});
    const clap_mod = clap.module("clap");

    // const libgit2_translate_c = b.addTranslateC(.{
    //     .target = target,
    //     .optimize = optimize,
    //     .root_source_file = libgit2_dep.path("include/git2.h"),
    // });
    // const libgit2_mod = libgit2_translate_c.createModule();

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // exe_mod.addCSourceFile(.{
    //     .file = b.path("src/git_utils.c"),
    //     .flags = &.{"-std=c99"},
    // });
    exe_mod.addImport("config", config.createModule());
    exe_mod.addImport("toml", toml_mod);
    exe_mod.addImport("clap", clap_mod);
    exe_mod.addImport("gitz", gitz_mod);
    // exe_mod.addImport("git2", libgit2_mod);
    exe_mod.linkLibrary(gitz_dep.artifact("gitz"));
    const exe = b.addExecutable(.{
        .name = "rucksack",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run rucksack");
    run_step.dependOn(&run_cmd.step);
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const version_step = b.step("version", "Get build version");
    version_step.dependOn(&version.step);
}

const Version = struct {
    step: std.Build.Step,
    version: std.SemanticVersion,

    pub fn init(b: *std.Build) !*Version {
        var tree = try std.zig.Ast.parse(b.allocator, @embedFile("build.zig.zon"), .zon);
        defer tree.deinit(b.allocator);

        const version = tree.tokenSlice(tree.nodes.items(.main_token)[2]);
        const semantic_version = try std.SemanticVersion.parse(version[1 .. version.len - 1]);

        const self = b.allocator.create(Version) catch @panic("OOM");
        self.step = std.Build.Step.init(.{
            .name = "version",
            .id = .custom,
            .owner = b,
            .makeFn = Version.make,
        });
        self.version = semantic_version;
        if (self.version.pre) |pre| {
            if (std.mem.eql(u8, pre, "git")) {
                const hash = b.run(&.{ "git", "rev-parse", "--short", "HEAD" });
                const trimmed = std.mem.trim(u8, hash, "\r\n ");
                self.version.pre = b.allocator.dupe(u8, trimmed) catch @panic("OOM");
            }
            if (std.mem.eql(u8, pre, "date")) {
                const date = b.run(&.{ "git", "log", "-1", "--format=%cs" });
                const replaced_date = std.mem.replaceOwned(u8, b.allocator, date, "-", "") catch unreachable;
                const trimmed = std.mem.trim(u8, replaced_date, "\r\n ");
                self.version.pre = b.allocator.dupe(u8, trimmed) catch @panic("OOM");
            }
        }
        return self;
    }

    pub fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *Version = @fieldParentPtr("step", step);
        try std.io.getStdOut().writer().print("{}\n", .{self.version});
    }
};
