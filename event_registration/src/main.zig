const std = @import("std");
const Io = std.Io;
const server = @import("server");
const auth = @import("auth");
const options = @import("options");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var diag: options.Diagnostic = .{};
    const opts = options.parse(args[1..], &diag) catch |err| {
        switch (err) {
            error.HelpRequested => {
                std.debug.print("{s}", .{options.usage});
                return;
            },
            error.UnknownFlag => std.debug.print("unknown argument: {s}\n", .{diag.arg}),
            error.MissingValue => std.debug.print("missing value for {s}\n", .{diag.arg}),
            error.InvalidPort => std.debug.print("invalid port: {s}\n", .{diag.arg}),
        }
        std.debug.print("{s}", .{options.usage});
        std.process.exit(2);
    };

    const address = options.resolveAddress(io, opts.address, opts.port) catch {
        std.debug.print("invalid address: {s} (use localhost or an IP)\n", .{opts.address});
        std.process.exit(2);
    };

    // Base URL of the Go auth service.
    const auth_url = init.environ_map.get("SIGA_AUTH_URL") orelse auth.default_url;

    var server_future = Io.async(io, server.start, .{ io, allocator, address, auth_url });
    _ = try server_future.await(io);
}
