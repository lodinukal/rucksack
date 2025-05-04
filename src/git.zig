var initialized = false;
pub fn init() bool {
    if (git2.git_libgit2_init() < 0) {
        return false;
    }
    initialized = true;
    return true;
}

pub fn deinit() bool {
    if (git2.git_libgit2_shutdown() < 0) {
        return false;
    }
    initialized = false;
    return true;
}

pub const Repository = opaque {
    pub const CloneOptions = struct {};

    pub fn clone(
        repo_url: [:0]const u8,
        path: [:0]const u8,
        options: CloneOptions,
    ) !*Repository {
        if (!initialized) return error.NotInitialized;
        _ = options;

        var git_options: git2.git_clone_options = .{};
        if (git2.git_clone_options_init(&git_options, git2.GIT_CLONE_OPTIONS_VERSION) < 0) {
            return error.CloneOptionsInitFailed;
        }

        git_options.fetch_opts.callbacks.credentials = @ptrCast(&cred_acquire_cb);

        var repo: ?*git2.git_repository = null;
        if (git2.git_clone(&repo, repo_url.ptr, path.ptr, &git_options) < 0) {
            return error.CloneFailed;
        }

        return @ptrCast(repo orelse return error.CloneFailed);
    }

    pub fn deinit(self: *Repository) void {
        git2.git_repository_free(@ptrCast(self));
    }
};

extern fn cred_acquire_cb(
    out: *?*git2.git_credential,
    url: ?[*:0]const u8,
    username_from_url: ?[*:0]const u8,
    allowed_types: u32,
    payload: *anyopaque,
) callconv(.c) c_int;

fn getErrorLast() !?*const git2.git_error {
    return git2.git_error_last();
}

const git2 = @cImport({
    @cInclude("git2.h");
});

const std = @import("std");
