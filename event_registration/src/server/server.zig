const std = @import("std");
const httpz = @import("httpz");
const repository = @import("repository");

pub const Server = @This();

const PutRequest = struct {
    name: []const u8,
};
const Response = struct {
    id: i32,
    name: []const u8,
};

var db: repository.Repository = undefined;

pub fn start(io: std.Io, allocator: std.mem.Allocator) !void {
    db = try repository.init();
    defer db.deinit();

    var server = try httpz.Server(void).init(
        io,
        allocator,
        .{ .address = .localhost(16000) },
        {},
    );
    defer {
        server.stop();
        server.deinit();
    }
    var router = try server.router(.{});
    router.get("/event/:id", handleGetEvent, .{});
    router.put("/event", handlePutEvent, .{});

    try server.listen();
}

fn sendError(res: *httpz.Response, status: u16, message: []const u8) !void {
    res.status = status;
    try res.json(.{ .@"error" = message }, .{});
}

fn handleGetEvent(req: *httpz.Request, res: *httpz.Response) !void {
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

fn handlePutEvent(req: *httpz.Request, res: *httpz.Response) !void {
    const maybe_request = req.json(PutRequest) catch {
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

    res.status = 200;
    try res.json(Response{
        .id = id,
        .name = request.name,
    }, .{});
}
