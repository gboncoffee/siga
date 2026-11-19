//! Command line options, in the same style as the Go auth service:
//! `-address <host>` and `-port <port>`. `--flag` and `-flag=value` also work.

const std = @import("std");

pub const default_address = "localhost";
pub const default_port: u16 = 16000;

pub const usage =
    \\usage: registration [-address <ip>] [-port <port>]
    \\
    \\  -address  address to listen to (default "localhost")
    \\  -port     port to listen to (default 16000)
    \\
;

pub const Options = struct {
    address: []const u8 = default_address,
    port: u16 = default_port,
};

pub const ParseError = error{ HelpRequested, UnknownFlag, MissingValue, InvalidPort };

/// On error, `diag` holds the offending argument.
pub const Diagnostic = struct {
    arg: []const u8 = "",
};

/// Parses `args`, without the program name.
pub fn parse(args: []const [:0]const u8, diag: *Diagnostic) ParseError!Options {
    var opts: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg: []const u8 = args[i];
        diag.arg = arg;

        if (arg.len < 2 or arg[0] != '-') return error.UnknownFlag;
        const flag = if (std.mem.startsWith(u8, arg, "--")) arg[2..] else arg[1..];

        var name = flag;
        var inline_value: ?[]const u8 = null;
        if (std.mem.indexOfScalar(u8, flag, '=')) |eq| {
            name = flag[0..eq];
            inline_value = flag[eq + 1 ..];
        }

        if (std.mem.eql(u8, name, "h") or std.mem.eql(u8, name, "help")) {
            return error.HelpRequested;
        }

        const is_address = std.mem.eql(u8, name, "address");
        const is_port = std.mem.eql(u8, name, "port");
        if (!is_address and !is_port) return error.UnknownFlag;

        const value = inline_value orelse blk: {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            break :blk args[i];
        };

        if (is_address) {
            if (value.len == 0) return error.MissingValue;
            opts.address = value;
        } else {
            diag.arg = value;
            opts.port = std.fmt.parseInt(u16, value, 10) catch return error.InvalidPort;
        }
    }
    return opts;
}

/// Turns the `-address` value into an IP address. Accepts `localhost` and
/// IPv4/IPv6 literals; other host names are not resolved.
pub fn resolveAddress(io: std.Io, address: []const u8, port: u16) !std.Io.net.IpAddress {
    if (std.ascii.eqlIgnoreCase(address, "localhost")) {
        return .{ .ip4 = .{ .bytes = .{ 127, 0, 0, 1 }, .port = port } };
    }
    return std.Io.net.IpAddress.resolve(io, address, port);
}

test "defaults" {
    var diag: Diagnostic = .{};
    const opts = try parse(&.{}, &diag);
    try std.testing.expectEqualStrings("localhost", opts.address);
    try std.testing.expectEqual(16000, opts.port);
}

test "flag forms" {
    var diag: Diagnostic = .{};
    const a = try parse(&.{ "-address", "0.0.0.0", "-port", "8000" }, &diag);
    try std.testing.expectEqualStrings("0.0.0.0", a.address);
    try std.testing.expectEqual(8000, a.port);

    const b = try parse(&.{ "--address=::1", "--port=9" }, &diag);
    try std.testing.expectEqualStrings("::1", b.address);
    try std.testing.expectEqual(9, b.port);
}

test "errors" {
    var diag: Diagnostic = .{};
    try std.testing.expectError(error.MissingValue, parse(&.{"-port"}, &diag));
    try std.testing.expectError(error.InvalidPort, parse(&.{ "-port", "70000" }, &diag));
    try std.testing.expectEqualStrings("70000", diag.arg);
    try std.testing.expectError(error.InvalidPort, parse(&.{"-port=abc"}, &diag));
    try std.testing.expectError(error.UnknownFlag, parse(&.{"-verbose"}, &diag));
    try std.testing.expectEqualStrings("-verbose", diag.arg);
    try std.testing.expectError(error.UnknownFlag, parse(&.{"solto"}, &diag));
    try std.testing.expectError(error.HelpRequested, parse(&.{"-h"}, &diag));
}
