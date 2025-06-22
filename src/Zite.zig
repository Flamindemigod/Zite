const std = @import("std");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

const Zite = @This();

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

const OpenError = error{
    Generic,
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
};

//Yoinked using the error message and code
//Msg crossref with sqlite.c:184202
inline fn ToError(val: c_int) OpenError!void {
    switch (val) {
        sqlite.SQLITE_CANTOPEN => return error.CantOpen,
        else => {
            std.debug.print("[Zite]: RC:{d}. sqlite error code is not handled\n", .{val});
            return error.Generic;
        },
    }
}

fn unwrapError(conn: ?*sqlite.sqlite3, val: c_int) !void {
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

pub fn open(path: []const u8, flags: []const OpenFlags) OpenError!Zite {
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

pub fn Key(comptime inner: type) type {
    const p = resolveProps(inner);
    if (p.len == 0) {
        return struct {
            inner: inner,
            const Self = @This();
            pub fn get(self: *const Self) inner {
                return self.inner;
            }
            pub fn set(val: inner) Self {
                return Self{ .inner = val };
            }
        };
    } else {
        return struct {
            inner: @FieldType(inner, "inner"),
            const Self = @This();
            pub fn get(self: *const Self) @FieldType(inner, "inner") {
                return self.inner;
            }
            pub fn set(val: @FieldType(inner, "inner")) Self {
                return Self{ .inner = val };
            }
        };
    }
}

pub fn Primary(comptime inner: type) type {
    const p = resolveProps(inner);
    if (p.len == 0) {
        return struct {
            inner: inner,
            const Self = @This();
            pub fn get(self: *const Self) inner {
                return self.inner;
            }
            pub fn set(val: inner) Self {
                return Self{ .inner = val };
            }
        };
    } else {
        return struct {
            inner: @FieldType(inner, "inner"),
            const Self = @This();
            pub fn get(self: *const Self) @FieldType(inner, "inner") {
                return self.inner;
            }
            pub fn set(val: @FieldType(inner, "inner")) Self {
                return Self{ .inner = val };
            }
        };
    }
}

fn resolveProps(comptime t: type) []Props {
    var prop_buffer: [16]Props = undefined;
    var count: u4 = 0;
    inline for (std.meta.fields(Props)) |v| {
        if (std.mem.containsAtLeast(u8, @typeName(t), 1, v.name)) {
            if (count < prop_buffer.len) {
                prop_buffer[count] = @enumFromInt(v.value);
                count += 1;
            }
        }
    }
    return prop_buffer[0..count];
}

const Props = enum {
    Primary,
    Key,
};

pub fn registerTable(self: *const Zite, comptime table: type, comptime name: []const u8) void {
    _ = self;
    const QueryString = comptime blk: {
        var Query: []const u8 = "CREATE TABLE IF NOT EXISTS " ++ name ++ "(";
        switch (@typeInfo(table)) {
            .@"struct" => |s| {
                for (s.fields, 0..) |f, i| {
                    switch (@typeInfo(f.type)) {
                        .@"struct" => {
                            const props = resolveProps(f.type);
                            if (props.len != 0) {
                                Query = Query ++ f.name;
                                switch (@typeInfo(@FieldType(f.type, "inner"))) {
                                    .int => Query = Query ++ " INTEGER ",
                                    else => |t| @compileLog(t),
                                }
                                for (props, 0..) |prop, pi| {
                                    for (@tagName(prop)) |p| {
                                        Query = Query ++ [1]u8{std.ascii.toUpper(p)};
                                    }
                                    if (pi < props.len - 1) Query = Query ++ " ";
                                }
                            }
                        },
                        .int => {
                            Query = Query ++ f.name ++ " INTEGER";
                        },
                        else => |t| @compileLog(t),
                    }
                    if (i < s.fields.len - 1) Query = Query ++ ", ";
                }
            },
            else => |t| @compileLog(t),
        }
        Query = Query ++ ");";
        break :blk Query;
    };
    std.debug.print("{s}\n", .{QueryString});
}

test "Open DB" {
    const testing = std.testing;
    const db = try Zite.open(".TestOpen.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestOpen.db") catch {});
    defer db.close();
    try testing.expect(true);
}

test "Register Table" {
    const test_struct = struct {
        id: Primary(Key(u8)),
        value: u16,
    };

    const testing = std.testing;
    const db = try Zite.open(".TestRegister.db", &.{ .create, .readwrite });
    defer (std.fs.cwd().deleteFile(".TestRegister.db") catch {});
    defer db.close();
    {
        db.registerTable(test_struct, "Main");
    }

    try testing.expect(true);
}
