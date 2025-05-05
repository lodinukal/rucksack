pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (is_debug) debug_allocator.allocator() else std.heap.smp_allocator;
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const stderr = std.io.getStdErr().writer();
    cli.cliMain(allocator, stderr) catch |err| {
        stderr.print("{s}\n", .{cli.help_message}) catch {};
        return switch (err) {
            // filter out errors that are not unexpected
            error.NameNotPartOfEnum,
            error.NoCommand,
            => return,
            else => err,
        };
    };
}

const std = @import("std");

const cli = @import("cli.zig");

const is_debug = @import("builtin").mode == .Debug;
