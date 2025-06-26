const std = @import("std");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

const Zite = @This();
pub const Constraints = @import("Constraints.zig");
pub const Utils = @import("Utils.zig");
db: *sqlite.sqlite3,
allocator: std.heap.ArenaAllocator,

//Only using the Valid Flags for Open.
//Verifed by looking at implementaions in sqlite3.c:185839
const OpenFlags = enum(c_int) {
    readonly = sqlite.SQLITE_OPEN_READONLY,
    readwrite = sqlite.SQLITE_OPEN_READWRITE,
    create = sqlite.SQLITE_OPEN_CREATE,
    nomutex = sqlite.SQLITE_OPEN_NOMUTEX,
    fullmutex = sqlite.SQLITE_OPEN_FULLMUTEX,
    privatecache = sqlite.SQLITE_OPEN_PRIVATECACHE,
    exrescode = sqlite.SQLITE_OPEN_EXRESCODE,
    sharedcache = sqlite.SQLITE_OPEN_SHAREDCACHE,
    autoproxy = sqlite.SQLITE_OPEN_AUTOPROXY,
    uri = sqlite.SQLITE_OPEN_URI,
    memory = sqlite.SQLITE_OPEN_MEMORY,
    nofollow = sqlite.SQLITE_OPEN_NOFOLLOW,
};

const NonErrorRetCodes: []const c_int = &.{ sqlite.SQLITE_OK, sqlite.SQLITE_ROW, sqlite.SQLITE_DONE };

const ZiteError = error{
    Generic,
    //Open Errors
    Perm,
    Corrupt,
    NotFound,
    CantOpen,
    CantOpenIsDir,
    CantOpenFullPath,
    CantOpenConvPath,
    CantOpenSymlink,
    NotADB,
    ROnlyRecovery,
    ROnlyRollback,
    ROnlyDBMoved,

    //Col Error
    Range,
    //Exec Errors
    Constraint,
};

//Yoinked using the error message and code
//Msg crossref with sqlite.c:184202
inline fn ToError(val: c_int) ZiteError!void {
    switch (val) {
        sqlite.SQLITE_CANTOPEN => return error.CantOpen,
        sqlite.SQLITE_CONSTRAINT => return error.Constraint,
        sqlite.SQLITE_RANGE => return error.Range,
        else => {
            std.debug.print("[Zite]: RC:{d}. sqlite error code is not handled\n", .{val});
            return error.Generic;
        },
    }
}

inline fn unwrapError(conn: ?*sqlite.sqlite3, val: c_int) ZiteError!void {
    const stderr = std.io.getStdErr().writer();
    if (conn == null) {
        stderr.print("[Zite]: {s}\n", .{sqlite.sqlite3_errmsg(conn)}) catch {};
        try ToError(sqlite.sqlite3_errcode(conn));
    }
    if (!std.mem.containsAtLeast(c_int, NonErrorRetCodes, 1, &.{val})) {
        stderr.print("[Zite]: {s}\n", .{sqlite.sqlite3_errmsg(conn)}) catch {};
        try ToError(sqlite.sqlite3_errcode(conn));
    }
}

pub fn init(allocator: std.mem.Allocator, path: []const u8, flags: []const OpenFlags) ZiteError!Zite {
    var db: ?*sqlite.sqlite3 = null;
    var flagVal: c_int = 0;
    for (flags) |f| {
        flagVal |= @intFromEnum(f);
    }
    const rc = sqlite.sqlite3_open_v2(path.ptr, @ptrCast(&db), flagVal, null);
    try unwrapError(db, rc);
    return .{ .db = db.?, .allocator = std.heap.ArenaAllocator.init(allocator) };
}

pub fn deinit(self: *const Zite) void {
    //We ignore the RetCode because we are closing regardless.
    _ = sqlite.sqlite3_close_v2(self.db);
    self.allocator.deinit();
}

inline fn ParseType(allocator: std.mem.Allocator, comptime field: type, value: [*c]u8) field {
    switch (@typeInfo(field)) {
        .int => {
            return std.fmt.parseInt(field, std.mem.span(value), 0) catch unreachable;
        },
        .@"enum" => |e| {
            return @enumFromInt(std.fmt.parseInt(e.tag_type, std.mem.span(value), 0) catch unreachable);
        },
        .optional => |o| {
            if (value == null) return null;
            return ParseType(allocator, o.child, value);
        },
        .pointer => |p| {
            if (p.child == u8 and p.size == .slice) {
                return allocator.dupe(u8, std.mem.span(value)) catch unreachable;
            } else {
                @compileError("Unimplemented");
            }
        },
        else => |s| {
            @compileLog(s, value);
        },
    }
}

pub fn exec(self: *Zite, comptime RetType: type, stmt: []const u8) !?std.ArrayList(RetType) {
    const exec_callback = struct {
        fn cb(ctx: ?*anyopaque, count: c_int, data: [*c][*c]u8, cols: [*c][*c]u8) callconv(.C) c_int {
            const builder: *?std.ArrayList(RetType) = @ptrCast(@alignCast(ctx));
            if (RetType == void) return 0;
            const structInfo: std.builtin.Type.Struct = switch (@typeInfo(RetType)) {
                .@"struct" => |s| s,
                else => @compileError("We dont support returning anything other than a struct\n"),
            };
            const t = builder.*.?.addOne() catch @panic("Out of Memory\n");
            const allocatorInner = builder.*.?.allocator;
            for (0..@intCast(count)) |i| {
                inline for (structInfo.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .@"struct" => |s| {
                            if (comptime Constraints.resolveProps(field.type).hasPropsSet()) {
                                if (std.mem.eql(u8, field.name, std.mem.span(cols[i]))) {
                                    @field(t, field.name) = .set(ParseType(allocatorInner, @FieldType(field.type, "inner"), data[i]));
                                }
                            } else {
                                inline for (s.fields) |sField| {
                                    if (std.mem.eql(u8, field.name ++ "_" ++ sField.name, std.mem.span(cols[i]))) {
                                        @field(@field(t, field.name), sField.name) = ParseType(allocatorInner, sField.type, data[i]);
                                    }
                                }
                            }
                        },
                        else => if (std.mem.eql(u8, field.name, std.mem.span(cols[i]))) {
                            @field(t, field.name) = ParseType(allocatorInner, field.type, data[i]);
                        },
                    }
                }
            }
            return 0;
        }
    }.cb;

    var builder: ?std.ArrayList(RetType) = if (RetType != void) std.ArrayList(RetType).init(self.allocator.allocator()) else null;
    try unwrapError(self.db, sqlite.sqlite3_exec(self.db, stmt.ptr, exec_callback, @ptrCast(&builder), null));
    return builder;
}

fn bindValue(self: *const Zite, stmt: ?*sqlite.sqlite3_stmt, idx: *c_int, comptime fieldType: type, value: fieldType) !void {
    const has_props = comptime Constraints.resolveProps(fieldType).getSetProps().len != 0;
    const field_type = if (has_props) @FieldType(fieldType, "inner") else fieldType;
    defer idx.* += 1;
    switch (@typeInfo(field_type)) {
        .int => try unwrapError(
            self.db,
            sqlite.sqlite3_bind_int(
                stmt,
                idx.*,
                @intCast(if (has_props) value.inner else value),
            ),
        ),
        .@"enum" => try unwrapError(
            self.db,
            sqlite.sqlite3_bind_int(
                stmt,
                idx.*,
                @intFromEnum(if (has_props) value.inner else value),
            ),
        ),
        .optional => |o| {
            if (value != null) return try self.bindValue(stmt, idx, o.child, value.?);
            try unwrapError(self.db, sqlite.sqlite3_bind_null(stmt, idx.*));
        },
        .@"struct" => |s| {
            idx.* -= 1;
            inline for (s.fields) |field| {
                try self.bindValue(stmt, idx, field.type, @field(value, field.name));
            }
        },
        .pointer => |p| {
            if (p.child == u8 and p.size == .slice) {
                try unwrapError(self.db, sqlite.sqlite3_bind_text(stmt, idx.*, value.ptr, @intCast(value.len), null));
            } else {
                @compileError("Unimplemented");
            }
        },
        else => |t| @compileLog(t),
    }
}

pub fn bindAndExec(self: *const Zite, comptime stmt: []const u8, value: anytype) !void {
    var ppStmt: ?*sqlite.sqlite3_stmt = null;
    try unwrapError(self.db, sqlite.sqlite3_prepare_v2(self.db, stmt.ptr, stmt.len, &ppStmt, null));
    var i: c_int = 1;
    inline for (std.meta.fields(@TypeOf(value))) |field| {
        try self.bindValue(ppStmt, &i, field.type, @field(value, field.name));
    }
    try unwrapError(self.db, sqlite.sqlite3_step(ppStmt));
}

test "Open DB" {
    const testing = std.testing;
    var db = try Zite.init(testing.allocator, ".TestOpen.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestOpen.db") catch {});
    defer db.deinit();
    try testing.expect(true);
}

test "Register Table" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;

    const test_struct = struct {
        id: NotNull(UniqueReplace(PrimaryKey(u8))) = .set(0),
        value: u32 = 69420,
    };

    const testing = std.testing;
    var db = try Zite.init(testing.allocator, ".TestRegister.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestRegister.db") catch {});
    defer db.deinit();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    try testing.expectEqualStrings("CREATE TABLE IF NOT EXISTS Main(id INTEGER PRIMARY KEY UNIQUE ON CONFLICT REPLACE NOT NULL ON CONFLICT FAIL, value INTEGER DEFAULT 69420);", stmt);
    _ = try db.exec(void, stmt);
}

test "Exec Callback" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;

    const test_struct = struct {
        id: NotNull(UniqueReplace(PrimaryKey(u8))) = .set(0),
        value: u16,
    };

    const testing = std.testing;
    var db = try Zite.init(testing.allocator, ".TestExec.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestExec.db") catch {});
    defer db.deinit();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    _ = try db.exec(void, stmt);
    _ = try db.exec(void, "INSERT INTO Main(id, value) VALUES (0, 1);");
    _ = try db.exec(void, "INSERT INTO Main(id, value) VALUES (1, 2);");
    var ret = try db.exec(test_struct, "SELECT * FROM Main;");
    defer ret.?.deinit();
    try std.testing.expectEqualDeep(ret.?.items[0], test_struct{ .id = .set(0), .value = 1 });
    try std.testing.expectEqualDeep(ret.?.items[1], test_struct{ .id = .set(1), .value = 2 });
}

test "Exec Insert Constraint Error" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;

    const test_struct = struct {
        id: NotNull(UniqueReplace(PrimaryKey(u8))) = .set(0),
        value: u16,
    };

    const testing = std.testing;
    var db = try Zite.init(testing.allocator, ".TestConstraintError.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestConstraintError.db") catch {});
    defer db.deinit();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    _ = try db.exec(void, stmt);
    _ = try db.exec(void, "INSERT INTO Main(id, value) VALUES (0, 1);");
    try std.testing.expectError(ZiteError.Constraint, db.exec(void, "INSERT INTO Main(id, value) VALUES (0, 1);"));
}

test "Zite Enum" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;

    const test_struct = struct {
        const v = enum {
            Test,
            Hello,
            Bruh,
        };
        id: NotNull(UniqueReplace(PrimaryKey(u8))) = .set(0),
        value: NotNull(v),
    };

    const testing = std.testing;
    var db = try Zite.init(testing.allocator, ".TestEnum.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestEnum.db") catch {});
    defer db.deinit();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    _ = try db.exec(void, stmt);
    _ = try db.exec(void, "INSERT INTO Main(id, value) VALUES (0, 1);");
    var ret = try db.exec(test_struct, "SELECT * FROM Main;");
    defer ret.?.deinit();
    try std.testing.expectEqualDeep(ret.?.items[0], test_struct{ .id = .set(0), .value = .set(.Hello) });
}

test "Zite Insert" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;

    const test_struct = struct {
        const v = enum {
            Test,
            Hello,
            Bruh,
        };
        id: NotNull(UniqueReplace(PrimaryKey(u8))) = .set(0),
        value: NotNull(v) = .set(.Test),
    };
    const testing = std.testing;
    var db = try Zite.init(testing.allocator, ".TestInsert.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestInsert.db") catch {});
    defer db.deinit();
    {
        const stmt = Utils.TableToCreateStatement(test_struct, "Main");
        _ = try db.exec(void, stmt);
    }
    var t = test_struct{ .value = .set(.Bruh) };
    const stmt = comptime Utils.InsertStatement(test_struct, "Main");
    try testing.expectEqualStrings("INSERT INTO Main(id, value) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET value=excluded.value;", stmt);
    {
        try db.bindAndExec(stmt, t);
        var ret = try db.exec(test_struct, "SELECT * FROM Main;");
        defer ret.?.deinit();
        try std.testing.expectEqualDeep(ret.?.items[0], test_struct{ .id = .set(0), .value = .set(.Bruh) });
    }
    {
        t.value = .set(.Hello);
        try db.bindAndExec(stmt, t);
        var ret = try db.exec(test_struct, "SELECT * FROM Main;");
        defer ret.?.deinit();
        try std.testing.expectEqualDeep(ret.?.items[0], test_struct{ .id = .set(0), .value = .set(.Hello) });
    }
}

test "Zite Null" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;

    const test_struct = struct {
        id: NotNull(UniqueReplace(PrimaryKey(u8))) = .set(0),
        value: ?u32 = 69420,
    };
    const testing = std.testing;
    var db = try Zite.init(testing.allocator, ".TestNull.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestNull.db") catch {});
    defer db.deinit();
    {
        const stmt = Utils.TableToCreateStatement(test_struct, "Main");
        _ = try db.exec(void, stmt);
    }
    var t = test_struct{};
    const stmt = comptime Utils.InsertStatement(test_struct, "Main");
    try testing.expectEqualStrings("INSERT INTO Main(id, value) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET value=excluded.value;", stmt);
    {
        try db.bindAndExec(stmt, t);
        var ret = try db.exec(test_struct, "SELECT * FROM Main;");
        defer ret.?.deinit();
        try std.testing.expectEqualDeep(test_struct{ .id = .set(0), .value = 69420 }, ret.?.items[0]);
    }
    {
        t.value = 42069;
        try db.bindAndExec(stmt, t);
        var ret = try db.exec(test_struct, "SELECT * FROM Main;");
        defer ret.?.deinit();
        try std.testing.expectEqualDeep(test_struct{ .id = .set(0), .value = 42069 }, ret.?.items[0]);
    }
}

// pub const Entry = struct {
//     id: Types.Int,
//     //Time in Seconds;
//     expiresIn: Types.Int,
//     idMal: ?Types.Int,
//     coverImage: Types.CoverImage,
//     bannerImage: ?Types.String,
//     title: Types.Titles,
//     description: ?Types.String,
//     type: Types.Media.Type,
//     format: Types.Media.Format,
//     source: Types.Media.Source,
//     season: ?Types.Media.Season,
//     seasonYear: ?Types.Int,
//     startDate: Types.Date,
//     endDate: Types.Date,
//     status: Types.Media.Status,
//     averageScore: ?Types.Int,
//
//     duration: ?Types.Int,
//     episodes: ?Types.Int,
//     chapters: ?Types.Int,
//     volumes: ?Types.Int,
//     countryOfOrigin: Types.String,
//     genres: []Types.String,
//     //TODO: Move Tags to a seperate table
//     //tags: []Types.Media.Tag,
//
//     pub const field_tags = .{
//         .id = Types.FieldType{ .PRIMARY_KEY = true },
//     };
// };

test "Zite MaoMao" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;
    _ = UniqueReplace;
    const test_struct = struct {
        const CoverImage = struct {
            large: []const u8 = "Hello there",
            medium: []const u8 = "Bruh",
            color: ?[]const u8 = null,
        };
        id: NotNull(PrimaryKey(u32)) = .set(1),
        //Time in Seconds;
        expiresIn: u32 = 0,
        idMal: ?u32 = 1,
        coverImage: CoverImage = .{},
        //     bannerImage: ?Types.String,
        //     title: Types.Titles,
        //     description: ?Types.String,
        //     type: Types.Media.Type,
        //     format: Types.Media.Format,
        //     source: Types.Media.Source,
        //     season: ?Types.Media.Season,
        //     seasonYear: ?u32,
        //     startDate: Types.Date,
        //     endDate: Types.Date,
        //     status: Types.Media.Status,
        //     averageScore: ?u32,
        //
        //     duration: ?u32,
        //     episodes: ?u32,
        //     chapters: ?u32,
        //     volumes: ?u32,
        //     countryOfOrigin: Types.String,
        //     genres: []Types.String,
    };
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var db = try Zite.init(testing.allocator, ".TestMaoMao.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestMaoMao.db") catch {});
    defer db.deinit();
    {
        const stmt = Utils.TableToCreateStatement(test_struct, "Main");
        _ = try db.exec(void, stmt);
    }
    const t = test_struct{};
    const stmt = comptime Utils.InsertStatement(test_struct, "Main");
    {
        try db.bindAndExec(stmt, t);
        var ret = try db.exec(test_struct, "SELECT * FROM Main;");
        defer ret.?.deinit();
        try std.testing.expectEqualDeep(t, ret.?.items[0]);
    }
}
