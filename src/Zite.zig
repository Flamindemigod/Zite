const std = @import("std");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

const Zite = @This();
pub const Constraints = @import("Constraints.zig");
pub const Utils = @import("Utils.zig");
db: *sqlite.sqlite3,

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

    //Exec Errors
    Constraint,
};

//Yoinked using the error message and code
//Msg crossref with sqlite.c:184202
inline fn ToError(val: c_int) ZiteError!void {
    switch (val) {
        sqlite.SQLITE_CANTOPEN => return error.CantOpen,
        sqlite.SQLITE_CONSTRAINT => return error.Constraint,
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

pub fn open(path: []const u8, flags: []const OpenFlags) ZiteError!Zite {
    var db: ?*sqlite.sqlite3 = null;
    var flagVal: c_int = 0;
    for (flags) |f| {
        flagVal |= @intFromEnum(f);
    }
    const rc = sqlite.sqlite3_open_v2(path.ptr, @ptrCast(&db), flagVal, null);
    try unwrapError(db, rc);
    return .{ .db = db.? };
}

pub fn close(self: *const Zite) void {
    //We ignore the RetCode because we are closing regardless.
    _ = sqlite.sqlite3_close_v2(self.db);
}

inline fn ParseType(comptime field: type, value: [*c]u8) field {
    switch (@typeInfo(field)) {
        .int => {
            return std.fmt.parseInt(field, std.mem.span(value), '_') catch unreachable;
        },
        .@"enum" => |e| {
            return @enumFromInt(std.fmt.parseInt(e.tag_type, std.mem.span(value), '_') catch unreachable);
        },
        else => |s| {
            @compileLog(s);
        },
    }
}

pub fn exec(self: *const Zite, comptime RetType: type, allocator: std.mem.Allocator, stmt: []const u8) !?std.ArrayList(RetType) {
    const exec_callback = struct {
        fn cb(ctx: ?*anyopaque, count: c_int, data: [*c][*c]u8, cols: [*c][*c]u8) callconv(.C) c_int {
            const builder: *?std.ArrayList(RetType) = @ptrCast(@alignCast(ctx));
            if (RetType == void) return 0;
            if (@typeInfo(RetType) != .@"struct") @compileError("We dont support returning anything other than a struct\n");
            const t = builder.*.?.addOne() catch @panic("Out of Memory\n");
            for (0..@intCast(count)) |i| {
                inline for (std.meta.fields(RetType)) |field| {
                    if (std.mem.eql(u8, field.name, std.mem.span(cols[i]))) {
                        if (comptime Constraints.resolveProps(field.type).len != 0) {
                            //@field(t.*, field.name).inner = std.fmt.parseInt(@FieldType(field.type, "inner"), std.mem.span(data[i]), '_') catch unreachable;
                            @field(t.*, field.name).inner = ParseType(@FieldType(field.type, "inner"), data[i]);
                        } else {
                            @field(t.*, field.name) = ParseType(field.type, data[i]);
                        }
                    }
                }
            }
            return 0;
        }
    }.cb;

    var builder: ?std.ArrayList(RetType) = if (RetType != void) std.ArrayList(RetType).init(allocator) else null;
    try unwrapError(self.db, sqlite.sqlite3_exec(self.db, stmt.ptr, exec_callback, @ptrCast(&builder), null));
    return builder;
}

test "Open DB" {
    const testing = std.testing;
    const db = try Zite.open(".TestOpen.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestOpen.db") catch {});
    defer db.close();
    try testing.expect(true);
}

test "Register Table" {
    const NotNull = Constraints.NotNull;
    const UniqueReplace = Constraints.UniqueReplace;
    const PrimaryKey = Constraints.PrimaryKey;

    const test_struct = struct {
        id: NotNull(UniqueReplace(PrimaryKey(u8))) = .set(0),
        value: u16,
    };

    const testing = std.testing;
    const db = try Zite.open(".TestRegister.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestRegister.db") catch {});
    defer db.close();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    try testing.expectEqualStrings(stmt, "CREATE TABLE IF NOT EXISTS Main(id INTEGER PRIMARY KEY UNIQUE ON CONFLICT REPLACE NOT NULL ON CONFLICT FAIL, value INTEGER);");
    _ = try db.exec(void, testing.allocator, stmt);
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
    const db = try Zite.open(".TestExec.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestExec.db") catch {});
    defer db.close();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    _ = try db.exec(void, testing.allocator, stmt);
    _ = try db.exec(void, testing.allocator, "INSERT INTO Main(id, value) VALUES (0, 1);");
    _ = try db.exec(void, testing.allocator, "INSERT INTO Main(id, value) VALUES (1, 2);");
    var ret = try db.exec(test_struct, testing.allocator, "SELECT * FROM Main;");
    defer ret.?.deinit();
    std.debug.print("{d}\n", .{ret.?.items.len});
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
    const db = try Zite.open(".TestConstraintError.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestConstraintError.db") catch {});
    defer db.close();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    _ = try db.exec(void, testing.allocator, stmt);
    _ = try db.exec(void, testing.allocator, "INSERT INTO Main(id, value) VALUES (0, 1);");
    try std.testing.expectError(ZiteError.Constraint, db.exec(void, testing.allocator, "INSERT INTO Main(id, value) VALUES (0, 1);"));
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
        value: v,
    };

    const testing = std.testing;
    const db = try Zite.open(".TestEnum.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestEnum.db") catch {});
    defer db.close();
    const stmt = Utils.TableToCreateStatement(test_struct, "Main");
    _ = try db.exec(void, testing.allocator, stmt);
    _ = try db.exec(void, testing.allocator, "INSERT INTO Main(id, value) VALUES (0, 1);");
    var ret = try db.exec(test_struct, testing.allocator, "SELECT * FROM Main;");
    defer ret.?.deinit();
    try std.testing.expectEqualDeep(ret.?.items[0], test_struct{ .id = .set(0), .value = .Hello });
}
