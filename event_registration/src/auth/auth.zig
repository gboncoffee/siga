//! Client for the SIGA authentication service (`auth/`, written in Go).
//!
//! The auth service hands out session tokens (UUIDs) on `POST /login` and
//! answers `GET /{uuid}` with 200 when the session exists, 401 when it does
//! not and 400 when the token is malformed. Clients of this service send the
//! token as `Authorization: Bearer <uuid>`.

const std = @import("std");

pub const Auth = @This();

pub const default_url = "http://localhost:8080";

/// Canonical textual UUID length: 8-4-4-4-12 hex digits.
const uuid_len = 36;

pub const Result = enum {
    authenticated,
    /// No `Authorization: Bearer` header, or the token is not a UUID.
    missing_token,
    /// The auth service does not know this session.
    invalid_token,
    /// The auth service could not be reached or gave an unexpected answer.
    unavailable,
};

client: std.http.Client,
base_url: []const u8,

/// `allocator` must be thread-safe: the client is shared by every worker.
/// `base_url` must outlive the returned value and have no trailing slash.
pub fn init(io: std.Io, allocator: std.mem.Allocator, base_url: []const u8) Auth {
    return .{
        .client = .{ .io = io, .allocator = allocator },
        .base_url = std.mem.trimEnd(u8, base_url, "/"),
    };
}

pub fn deinit(a: *Auth) void {
    a.client.deinit();
}

/// Checks the value of an `Authorization` header against the auth service.
/// Safe to call from several threads at once.
pub fn authenticate(a: *Auth, authorization: ?[]const u8) Result {
    const token = tokenFromHeader(authorization) orelse return .missing_token;
    return a.validate(token);
}

/// Asks the auth service whether `token` is an open session.
pub fn validate(a: *Auth, token: []const u8) Result {
    // The token goes into the URL path, so only ever send a well-formed UUID.
    if (!isUuid(token)) return .missing_token;

    var url_buf: [512]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}/{s}", .{ a.base_url, token }) catch {
        std.log.err("auth: base url too long: {s}", .{a.base_url});
        return .unavailable;
    };

    const result = a.client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .redirect_behavior = .unhandled,
    }) catch |err| {
        std.log.err("auth: request to {s} failed: {t}", .{ a.base_url, err });
        return .unavailable;
    };

    return switch (result.status) {
        .ok => .authenticated,
        .unauthorized, .bad_request => .invalid_token,
        else => |status| {
            std.log.err("auth: unexpected status {d}", .{@intFromEnum(status)});
            return .unavailable;
        },
    };
}

/// Extracts the token from an `Authorization: Bearer <token>` header value.
pub fn tokenFromHeader(authorization: ?[]const u8) ?[]const u8 {
    const value = std.mem.trim(u8, authorization orelse return null, " \t");
    const scheme = "bearer ";
    if (value.len <= scheme.len) return null;
    if (!std.ascii.eqlIgnoreCase(value[0..scheme.len], scheme)) return null;

    const token = std.mem.trim(u8, value[scheme.len..], " \t");
    return if (token.len == 0) null else token;
}

/// Whether `s` is a UUID in canonical `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` form.
pub fn isUuid(s: []const u8) bool {
    if (s.len != uuid_len) return false;
    for (s, 0..) |c, i| switch (i) {
        8, 13, 18, 23 => if (c != '-') return false,
        else => if (!std.ascii.isHex(c)) return false,
    };
    return true;
}

test tokenFromHeader {
    const t = std.testing;
    try t.expectEqualStrings("abc", tokenFromHeader("Bearer abc").?);
    try t.expectEqualStrings("abc", tokenFromHeader("bearer   abc ").?);
    try t.expectEqual(null, tokenFromHeader(null));
    try t.expectEqual(null, tokenFromHeader("Bearer "));
    try t.expectEqual(null, tokenFromHeader("Basic abc"));
    try t.expectEqual(null, tokenFromHeader("abc"));
}

test isUuid {
    const t = std.testing;
    try t.expect(isUuid("0b9f6a3e-8f1c-4c55-9d2e-3a7b1c2d4e5f"));
    try t.expect(isUuid("0B9F6A3E-8F1C-4C55-9D2E-3A7B1C2D4E5F"));
    try t.expect(!isUuid("0b9f6a3e8f1c4c559d2e3a7b1c2d4e5f"));
    try t.expect(!isUuid("0b9f6a3e-8f1c-4c55-9d2e-3a7b1c2d4e5g"));
    try t.expect(!isUuid("../login/aaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
    try t.expect(!isUuid(""));
}
