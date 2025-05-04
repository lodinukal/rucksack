pub const Subcommand = enum {
    /// display help information
    help,
    /// version
    version,
    /// create a new rucksack.toml file, if it doesn't exist
    init,
    /// like npm install, install dependencies listed in the rucksack.toml file (recursively)
    install,
    /// remove all installed packages
    clean,
};

const main_parsers = .{
    .command = clap.parsers.enumeration(Subcommand),
};

pub const help_message =
    \\Rucksack is a dependency manager for remote git sources.
    \\
    \\Subcommands:
    \\  help       Display this help and exit.
    \\  version    Display the version and exit.
    \\  init       Create a new rucksack.toml file, if it doesn't exist.
    \\  install    Install dependencies listed in the rucksack.toml file (recursively).
    \\  clean      Remove all installed packages.
    \\
;

pub const params_string =
    \\<command>
    \\
;

const main_params = clap.parseParamsComptime(params_string);

const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

pub fn cliMain(allocator: std.mem.Allocator, err_stream: anytype) !void {
    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    _ = iter.next();
    var diag: clap.Diagnostic = .{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,

        // Terminate the parsing of arguments after parsing the first positional (0 is passed
        // here because parsed positionals are, like slices and arrays, indexed starting at 0).
        //
        // This will terminate the parsing after parsing the subcommand enum and leave `iter`
        // not fully consumed. It can then be reused to parse the arguments for subcommands.
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(err_stream, err) catch {};
        return err;
    };
    defer res.deinit();

    var parser: toml.Parser(rucksack_file.RucksackFile) = .init(allocator);
    defer parser.deinit();
    var result: ?toml.Parsed(rucksack_file.RucksackFile) = parser.parseFile("./" ++ rucksack_file.rucksack_file_name) catch null;
    defer if (result) |*r| r.deinit();

    const command = res.positionals[0] orelse return error.NoCommand;
    switch (command) {
        .help => {
            std.debug.print("{s}\n", .{help_message});
            return;
        },
        .version => {
            std.debug.print("{}\n", .{config.version});
            return;
        },
        .init => {
            rucksack_file.createDefault(std.fs.cwd()) catch |err| switch (err) {
                error.RucksackFileAlreadyExists => {
                    std.debug.print("Rucksack file already exists\n", .{});
                    return;
                },
                else => {
                    std.debug.print("Failed to create rucksack file: {}\n", .{err});
                    return err;
                },
            };
        },
        .install => {
            if (result) |r| {
                const path = r.value.path orelse rucksack_file.default_path;
                try cleanPath(path);
                try rucksack_file.install(r.value);
                return;
            }
            std.debug.print("No rucksack file found, skipping install\n", .{});
        },
        .clean => {
            if (result) |r| {
                const path = r.value.path orelse rucksack_file.default_path;
                try cleanPath(path);
                return;
            }
            std.debug.print("No rucksack file found, skipping clean\n", .{});
        },
    }
}

fn cleanPath(path: []const u8) !void {
    // std.debug.print("Cleaning path: {s}\n", .{path});
    std.fs.cwd().deleteTree(path) catch |err| switch (err) {
        else => {
            std.debug.print("Failed to delete path: {}\n", .{err});
            return err;
        },
    };
}

const clap = @import("clap");
const std = @import("std");
const toml = @import("toml");

const config = @import("config");

const rucksack_file = @import("rucksack_file.zig");
