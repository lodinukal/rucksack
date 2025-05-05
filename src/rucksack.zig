pub const Config = struct {
    path: ?[]const u8,
    dependencies: toml.HashMap([]const u8),
};

pub const SourceKind = enum {
    git,
    tar,
};

pub const file_name = "rucksack.toml";
pub const default_path = "packages";

pub const default_rucksack = @embedFile("default_rucksack.toml");

pub fn hasRucksackFile(dir: std.fs.Dir) bool {
    dir.access(file_name, .{}) catch return false;
    return true;
}

pub fn createDefault(dir: std.fs.Dir) !void {
    if (hasRucksackFile(dir)) {
        return error.RucksackFileAlreadyExists;
    }

    const file = try dir.createFile(file_name, .{ .truncate = false });
    defer file.close();
    try file.writeAll(default_rucksack);
}

pub fn load(allocator: std.mem.Allocator, dir: std.fs.Dir, use_ancestry: bool) ?struct { toml.Parsed(Config), std.fs.Dir } {
    var parser: toml.Parser(Config) = .init(allocator);
    defer parser.deinit();

    const rucksack_dir = if (use_ancestry) findFileInAncestry(dir, file_name) orelse return null else dir;

    const file = rucksack_dir.openFile(file_name, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(parser.alloc, 1024 * 1024 * 1024) catch return null;
    defer parser.alloc.free(content);

    const parsed = parser.parseString(content) catch return null;
    return .{ parsed, rucksack_dir };
}

pub fn install(allocator: std.mem.Allocator, dir: std.fs.Dir, use_ancestry: bool) !void {
    const config, const rucksack_dir = load(allocator, dir, use_ancestry) orelse return error.NoConfig;
    defer config.deinit();
    const path = config.value.path orelse default_path;
    try cleanPath(rucksack_dir, path);
    try installConfig(allocator, rucksack_dir, config.value);
}

pub const InstallConfigError = error{
    NoConfig,
    InvalidSourceKind,
    InvalidSource,
} || std.fs.Dir.OpenError ||
    std.fs.Dir.MakeError ||
    std.mem.Allocator.Error || GitError ||
    error{ FileTooBig, FileBusy, FileSystem, UnrecognizedVolume } ||
    std.fs.Dir.StatFileError;

const GitError = error{
    Generic,
    NotFound,
    Exists,
    Ambiguous,
    BufferSize,
    User,
    BareRepo,
    UnbornBranch,
    Unmerged,
    NonFastForward,
    InvalidSpec,
    Conflict,
    Locked,
    Modified,
    Auth,
    Certificate,
    Applied,
    Peel,
    Eof,
    Invalid,
    Uncommitted,
    Directory,
    MergeConflict,
    Passthrough,
    Iterover,
    Retry,
    Mismatch,
    IndexDirty,
    ApplyFail,
    Owner,
    Timeout,
    Unchanged,
    NotSupported,
    Readonly,
};

pub fn installConfig(allocator: std.mem.Allocator, dir: std.fs.Dir, config: Config) InstallConfigError!void {
    const path = config.path orelse default_path;

    // ensure the path exists
    const output_dir = try dir.makeOpenPath(path, .{});

    var buf: [512]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const small_allocator = fba.allocator();

    var it = config.dependencies.map.iterator();
    while (it.next()) |entry| {
        fba.reset();

        var token_it = std.mem.tokenizeScalar(u8, entry.value_ptr.*, ' ');
        const source_kind_str = token_it.next() orelse return error.InvalidSourceKind;
        const source_kind = std.meta.stringToEnum(SourceKind, source_kind_str) orelse return error.InvalidSourceKind;
        const source = token_it.next() orelse return error.InvalidSource;

        const output_path = try std.fs.path.joinZ(small_allocator, &.{ path, entry.key_ptr.* });
        const source_z = try small_allocator.dupeZ(u8, source);

        switch (source_kind) {
            .git => {
                // we need to set the cwd so git2 can clone properly
                try dir.setAsCwd();
                const repo = try gitz.Repository.clone(source_z, output_path);
                defer repo.deinit();
                try std.fs.cwd().setAsCwd();
            },
            .tar => {
                std.debug.print("Tar source: {s}\n", .{source});
            },
        }

        const install_dir = try output_dir.openDir(entry.key_ptr.*, .{});
        // std.debug.print("Installing {s} to {s}\n", .{ source, output_path });
        install(allocator, install_dir, false) catch |err| switch (err) {
            error.NoConfig => {},
            else => {
                std.debug.print("Failed to install {s} to {s}\n", .{ source, output_path });
                return err;
            },
        };
    }
}

pub fn clean(allocator: std.mem.Allocator, dir: std.fs.Dir) !void {
    const config, const rucksack_dir = load(allocator, dir, true) orelse return error.NoConfig;
    defer config.deinit();
    const path = config.value.path orelse default_path;
    try cleanPath(rucksack_dir, path);
}

const max_ancestry_depth = 10;
fn findFileInAncestry(dir: std.fs.Dir, name: []const u8) ?std.fs.Dir {
    var pointer_dir = dir;
    var depth: usize = 0;
    while (true) : (depth += 1) {
        defer depth += 1;
        if (depth > max_ancestry_depth) {
            return null;
        }
        const current_dir = pointer_dir;
        pointer_dir = pointer_dir.openDir("..", .{}) catch return null;
        if (current_dir.access(name, .{})) {
            return current_dir;
        } else |_| continue;
    }
    return null;
}

fn cleanPath(dir: std.fs.Dir, path: []const u8) !void {
    // std.debug.print("Cleaning path: {s}\n", .{path});
    dir.deleteTree(path) catch |err| switch (err) {
        else => {
            std.debug.print("Failed to delete path: {}\n", .{err});
            return err;
        },
    };
}

const toml = @import("toml");
const std = @import("std");
const gitz = @import("gitz");
