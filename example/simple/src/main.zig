const std = @import("std");
const Zite = @import("Zite");

const User = struct {
    const Gender = enum {
        male,
        female,
    };
    const Name = struct {
        const Title = enum {
            Madame,
            Mademoiselle,
            Monsieur,
            Mr,
            Mrs,
            Ms,
            Miss,
        };
        title: Title,
        first: []const u8,
        last: []const u8,
    };
    const Location = struct {
        street: struct {
            number: u16,
            name: []const u8,
        },
        city: []const u8,
        state: []const u8,
        country: []const u8,
        //postcode: std.json.Value,
        coordinates: struct {
            latitude: []const u8,
            longitude: []const u8,
        },
        timezone: struct {
            offset: []const u8,
            description: []const u8,
        },
    };
    const Login = struct {
        uuid: []const u8,
        username: []const u8,
        password: []const u8,
        salt: []const u8,
        md5: []const u8,
        sha1: []const u8,
        sha256: []const u8,
    };
    const DoB = struct {
        date: []const u8,
        age: u16,
    };
    gender: Gender,
    name: Name,
    location: Location,
    email: []const u8,
    login: Login,
    dob: DoB,
    registered: DoB,
    phone: []const u8,
    cell: []const u8,
    id: struct {
        name: []const u8,
        value: ?[]const u8,
    },
    picture: struct {
        large: []const u8,
        medium: []const u8,
        thumbnail: []const u8,
    },
    nat: enum {
        AU,
        BR,
        CA,
        CH,
        DE,
        DK,
        ES,
        FI,
        FR,
        GB,
        IE,
        IN,
        IR,
        LEGO,
        MX,
        NL,
        NO,
        NZ,
        RS,
        TR,
        UA,
        US,
    },
};

const DBUser = blk: {
    var userT = @typeInfo(User);
    var structFields: []const std.builtin.Type.StructField = std.meta.fields(User);
    structFields = structFields ++ &[1]std.builtin.Type.StructField{.{ .name = "key", .is_comptime = false, .alignment = 0, .type = Zite.Constraints.PrimaryKey(?u32), .default_value_ptr = &Zite.Constraints.PrimaryKey(?u32).set(null) }};
    userT.@"struct".fields = structFields;
    userT.@"struct".layout = .auto;
    break :blk @Type(userT);
};

const writer = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try Zite.init(allocator, "Test.db", &.{ .create, .readwrite });
    defer db.deinit();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    var storage = std.ArrayList(u8).init(allocator);
    defer storage.deinit();
    var timer = try std.time.Timer.start();
    _ = try client.fetch(.{ .method = .GET, .location = .{ .url = "https://randomuser.me/api/1.4/?results=1000" }, .response_storage = .{ .dynamic = &storage } });
    try writer.print("Fetched Data from API in {d} ms\n", .{timer.lap() / std.time.ns_per_ms});
    const data = try std.json.parseFromSlice(struct { results: []User }, allocator, storage.items, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer data.deinit();
    try writer.print("Parsed JSON Data in {d} ms\n", .{timer.lap() / std.time.ns_per_ms});
    {
        const stmt = comptime Zite.Utils.TableToCreateStatement(DBUser, "User");
        _ = try db.exec(void, stmt);
        try writer.print("Created Table in {d} ms\n", .{timer.lap() / std.time.ns_per_ms});
    }
    _ = try db.exec(void, "BEGIN TRANSACTION"); //TODO: Move To Library
    {
        const stmt = comptime Zite.Utils.InsertStatement(DBUser, "User");
        for (data.value.results) |res| {
            try db.bindAndExec(stmt, res);
        }
    }
    _ = try db.exec(void, "END TRANSACTION"); //TODO: Move To Library
    try writer.print("Inserted {d} Entries in {d} ms\n", .{ data.value.results.len, timer.lap() / std.time.ns_per_ms });
}
