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
    /// gets information about the current environment
    env,
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
    \\  env        Get information about the current environment.
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

    const rucksack_file: ?toml.Parsed(rucksack.Config), const rucksack_dir = rucksack.load(allocator, std.fs.cwd(), true) orelse
        .{ null, std.fs.cwd() };
    defer if (rucksack_file) |r| r.deinit();

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
            rucksack.createDefault(rucksack_dir) catch |err| switch (err) {
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
            try rucksack.install(allocator, rucksack_dir, true);
        },
        .clean => {
            try rucksack.clean(allocator, rucksack_dir);
        },
        .env => {
            var max_path: [std.fs.max_path_bytes]u8 = undefined;
            std.debug.print("Environment information:\n", .{});
            std.debug.print("  Current working directory: {s}\n", .{try rucksack_dir.realpath("", &max_path)});
            std.debug.print("  Has rucksack file: {}\n", .{rucksack.hasRucksackFile(rucksack_dir)});
            return;
        },
    }
}

const clap = @import("clap");
const std = @import("std");
const toml = @import("toml");

const config = @import("config");

const rucksack = @import("rucksack.zig");
