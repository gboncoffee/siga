const std = @import("std");
const httpz = @import("httpz");
const repository = @import("repository");
const auth = @import("auth");

pub const Server = @This();

const PostRequest = struct {
    name: []const u8,
};
const Response = struct {
    id: i32,
    name: []const u8,
};

var db: repository.Repository = undefined;
var authenticator: auth.Auth = undefined;

pub fn start(
    io: std.Io,
    allocator: std.mem.Allocator,
    address: std.Io.net.IpAddress,
    auth_url: []const u8,
) !void {
    db = try repository.init();
    defer db.deinit();

    authenticator = auth.init(io, allocator, auth_url);
    defer authenticator.deinit();
    std.log.info("using auth service at {s}", .{authenticator.base_url});

    var server = try httpz.Server(void).init(
        io,
        allocator,
        .{ .address = .{ .ip = address } },
        {},
    );
    defer {
        server.stop();
        server.deinit();
    }
    var router = try server.router(.{});
    router.get("/event", handleListEvents, .{});
    router.get("/event/:id", handleGetEvent, .{});
    router.post("/event", handlePostEvent, .{});

    std.log.info("listening on {f}", .{address});
    try server.listen();
}

fn sendError(res: *httpz.Response, status: u16, message: []const u8) !void {
    res.status = status;
    try res.json(.{ .@"error" = message }, .{});
}

/// Answers the request with an error and returns false unless it carries a
/// valid session token.
fn requireAuth(req: *httpz.Request, res: *httpz.Response) !bool {
    switch (authenticator.authenticate(req.header("authorization"))) {
        .authenticated => return true,
        .missing_token => {
            res.header("WWW-Authenticate", "Bearer");
            try sendError(res, 401, "missing or malformed token");
        },
        .invalid_token => {
            res.header("WWW-Authenticate", "Bearer");
            try sendError(res, 401, "invalid token");
        },
        .unavailable => try sendError(res, 503, "auth service unavailable"),
    }
    return false;
}

fn handleListEvents(req: *httpz.Request, res: *httpz.Response) !void {
    if (!try requireAuth(req, res)) return;

    const events = db.findAll(res.arena) catch |err| {
        std.log.err("findAll failed: {t}", .{err});
        return sendError(res, 500, "internal error");
    };

    res.status = 200;
    try res.json(events, .{});
}

fn handleGetEvent(req: *httpz.Request, res: *httpz.Response) !void {
    if (!try requireAuth(req, res)) return;

    const raw_id = req.param("id") orelse return sendError(res, 400, "missing id");
    const id = std.fmt.parseInt(i32, raw_id, 10) catch {
        return sendError(res, 400, "invalid id");
    };

    const maybe_event = db.findById(id) catch |err| {
        std.log.err("findById({d}) failed: {t}", .{ id, err });
        return sendError(res, 500, "internal error");
    };
    const event = maybe_event orelse return sendError(res, 404, "not found");

    res.status = 200;
    try res.json(Response{
        .id = event.id,
        .name = std.mem.sliceTo(&event.name, 0),
    }, .{});
}

fn handlePostEvent(req: *httpz.Request, res: *httpz.Response) !void {
    if (!try requireAuth(req, res)) return;

    const maybe_request = req.json(PostRequest) catch {
        return sendError(res, 400, "invalid body");
    };
    const request = maybe_request orelse return sendError(res, 400, "missing body");

    if (request.name.len == 0) {
        return sendError(res, 400, "name is empty");
    }
    if (request.name.len > repository.name_size) {
        return sendError(res, 400, "name too big");
    }

    const id = db.insertByName(request.name) catch |err| {
        std.log.err("insertByName failed: {t}", .{err});
        return sendError(res, 500, "internal error");
    };

    res.status = 201;
    res.header("Location", try std.fmt.allocPrint(res.arena, "/event/{d}", .{id}));
    try res.json(Response{
        .id = id,
        .name = request.name,
    }, .{});
}
