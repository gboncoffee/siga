const std = @import("std");
const sqlite = @import("sqlite");

pub const Repository = @This();

/// Maximum event name length, in bytes.
pub const name_size: usize = 128;
pub const Event = struct {
    id: i32,
    // zig-sqlite requires a sentinel-terminated array to be strictly larger
    // than the stored text, so reserve one extra byte to fit `name_size`.
    name: [name_size + 1:0]u8,
};

/// Event row with a heap-allocated name, used when listing.
pub const EventEntry = struct {
    id: i32,
    name: []const u8,
};

db: sqlite.Db,

pub fn init() !Repository {
    std.debug.print("Hello, World!\n", .{});
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "events.db" },
        .open_flags = .{ .create = true, .write = true },
        // The connection is shared by every httpz worker thread, so SQLite
        // must serialize access to it.
        .threading_mode = .Serialized,
    });

    try db.exec(
        "create table if not exists events(id integer primary key, name text)",
        .{},
        .{},
    );

    const query = "insert or ignore into events(id, name) values(?, ?)";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .id = 57,
        .name = "Main event",
    });

    return Repository{ .db = db };
}

pub fn deinit(r: *Repository) void {
    r.db.deinit();
}

/// Inserts a new event and returns its id.
pub fn insertByName(r: *Repository, name: []const u8) !i32 {
    const query = "insert into events(name) values(?) returning id";
    const id = try r.db.one(i32, query, .{}, .{ .name = name });
    return id orelse error.InsertFailed;
}

pub fn findById(r: *Repository, event_id: i32) !?Event {
    const query = "select id, name from events where id = ?";
    const row = try r.db.one(Event, query, .{}, .{ .id = event_id });

    if (row) |event| {
        std.debug.print("found event by id: {any}\n", .{event});
    }

    return row;
}

pub fn findByName(r: *Repository, event_name: []const u8) !?Event {
    const query = "select id, name from events where name = ?";
    const row = try r.db.one(Event, query, .{}, .{ .name = event_name });

    if (row) |event| {
        std.debug.print("found event by name: {any}\n", .{event});
    }

    return row;
}

/// Returns every event ordered by id. Memory is owned by `allocator`.
pub fn findAll(r: *Repository, allocator: std.mem.Allocator) ![]EventEntry {
    const query = "select id, name from events order by id";
    var stmt = try r.db.prepare(query);
    defer stmt.deinit();

    return stmt.all(EventEntry, allocator, .{}, .{});
}
