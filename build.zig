const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config = b.addOptions();
    const version = try Version.init(b);
    config.addOption(std.SemanticVersion, "version", version.version);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
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
