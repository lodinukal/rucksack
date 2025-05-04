pub const RucksackFile = struct {
    path: ?[]const u8,
    dependencies: toml.HashMap([]const u8),
};

pub const SourceKind = enum {
    git,
    tar,
};

pub const rucksack_file_name = "rucksack.toml";
pub const default_path = "packages";

pub const default_rucksack = @embedFile("default_rucksack.toml");

pub fn hasRucksackFile(dir: std.fs.Dir) bool {
    dir.access(rucksack_file_name, .{}) catch return false;
    return true;
}

pub fn createDefault(dir: std.fs.Dir) !void {
    if (hasRucksackFile(dir)) {
        return error.RucksackFileAlreadyExists;
    }

    const file = try dir.createFile(rucksack_file_name, .{ .truncate = false });
    defer file.close();
    try file.writeAll(default_rucksack);
}

pub fn install(file: RucksackFile) !void {
    const path = file.path orelse default_path;

    // ensure the path exists
    std.fs.cwd().makeDir(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var buf: [512]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const allocator = fba.allocator();

    var it = file.dependencies.map.iterator();
    while (it.next()) |entry| {
        fba.reset();

        var token_it = std.mem.tokenizeScalar(u8, entry.value_ptr.*, ' ');
        const source_kind_str = token_it.next() orelse return error.InvalidSourceKind;
        const source_kind = std.meta.stringToEnum(SourceKind, source_kind_str) orelse return error.InvalidSourceKind;
        const source = token_it.next() orelse return error.InvalidSource;

        const output_path = try std.fs.path.joinZ(allocator, &.{ path, entry.key_ptr.* });
        defer allocator.free(output_path);

        const source_z = try allocator.dupeZ(u8, source);
        defer allocator.free(source_z);

        switch (source_kind) {
            .git => {
                const repo = try gitz.Repository.clone(source_z, output_path);
                defer repo.deinit();
            },
            .tar => {
                std.debug.print("Tar source: {s}\n", .{source});
            },
        }
    }
}

const toml = @import("toml");
const std = @import("std");
const gitz = @import("gitz");
