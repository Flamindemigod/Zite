const std = @import("std");
pub const Constraints = @import("Constraints.zig");

pub fn InsertStatement(comptime table: type, comptime name: []const u8) []const u8 {
    const QueryString = comptime blk: {
        var Query: []const u8 = "INSERT INTO " ++ name ++ "(";
        switch (@typeInfo(table)) {
            .@"struct" => |s| {
                var primary: []const u8 = undefined;
                for (s.fields, 0..) |f, i| {
                    const props = Constraints.resolveProps(f.type);
                    if (props.PrimaryKey) primary = f.name;
                    Query = Query ++ f.name;
                    if (i < s.fields.len - 1) Query = Query ++ ", ";
                }
                Query = Query ++ ")";
                Query = Query ++ " VALUES (";
                for (0..s.fields.len) |i| {
                    Query = Query ++ "?";
                    if (i < s.fields.len - 1) Query = Query ++ ", ";
                }
                Query = Query ++ ") ON CONFLICT(" ++ primary ++ ") DO UPDATE SET ";
                for (s.fields, 0..) |f, i| {
                    if (std.mem.eql(u8, f.name, primary)) continue;
                    Query = Query ++ f.name ++ "=excluded." ++ f.name;
                    if (i < s.fields.len - 1) Query = Query ++ ", ";
                }
                Query = Query ++ ";";
            },
            else => |t| @compileLog(t),
        }
        break :blk Query;
    };
    return QueryString;
}

fn genCreateForType(comptime ftype: type, comptime name: []const u8, i: usize, comptime props: Constraints.PropFields, dv: ?ftype) []const u8 {
    var Query: []const u8 = "";
    switch (@typeInfo(ftype)) {
        .@"struct" => comptime {
            const ps = Constraints.resolveProps(ftype);
            if (!props.hasPropsSet()) {
                Query = Query ++ genCreateForType(@FieldType(ftype, "inner"), name, i, ps, if (dv) |dvu| dvu.get() else null);
            }
        },
        .int => {
            Query = Query ++ name ++ " INTEGER";
            const propArr = props.getSetProps();
            for (propArr) |prop| {
                Query = std.fmt.comptimePrint("{s} {s}", .{ Query, Constraints.Props.Values[@intFromEnum(prop)] });
            }
            if (!props.PrimaryKey) {
                if (dv) |dvu| Query = std.fmt.comptimePrint("{s} DEFAULT {d}", .{ Query, dvu });
            }
        },
        .@"enum" => {
            Query = Query ++ name ++ " INTEGER ";
            const propArr = props.getSetProps();
            for (propArr, 0..) |prop, pi| {
                Query = Query ++ Constraints.Props.Values[@intFromEnum(prop)];
                if (pi < propArr.len - 1) Query = Query ++ " ";
            }
            if (!props.PrimaryKey) {
                if (dv) |dvu| Query = std.fmt.comptimePrint("{s} DEFAULT {d}", .{ Query, @intFromEnum(dvu) });
            }
        },
        .optional => |o| {
            Query = Query ++ genCreateForType(o.child, name, i, props, if (dv) |dvu| dvu else null);
        },
        else => |t| @compileLog(t),
    }
    return Query;
}

pub fn TableToCreateStatement(comptime table: type, comptime name: []const u8) []const u8 {
    const QueryString = comptime blk: {
        var Query: []const u8 = "CREATE TABLE IF NOT EXISTS " ++ name ++ "(";
        switch (@typeInfo(table)) {
            .@"struct" => |s| {
                for (s.fields, 0..) |f, i| {
                    Query = Query ++ genCreateForType(f.type, f.name, i, .{}, f.defaultValue());
                    if (i < s.fields.len - 1) Query = Query ++ ", ";
                }
            },
            else => |t| @compileLog(t),
        }
        Query = Query ++ ");";
        break :blk Query;
    };
    return QueryString;
}
