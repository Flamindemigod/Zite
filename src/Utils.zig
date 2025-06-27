const std = @import("std");
pub const Constraints = @import("Constraints.zig");

fn genInsertConflicts(comptime fieldType: type, name: []const u8) []const u8 {
    var Query: []const u8 = "";
    switch (@typeInfo(fieldType)) {
        .@"struct" => |s| {
            if (Constraints.resolveProps(fieldType).hasPropsSet()) {
                Query = std.fmt.comptimePrint("{s}{s}=excluded.{s}", .{ Query, name, name });
            } else {
                for (s.fields, 0..) |field, i| {
                    if (i > 0) Query = Query ++ " ";
                    Query = Query ++ genInsertConflicts(field.type, name ++ "_" ++ field.name);
                    if (i < s.fields.len - 1) Query = Query ++ ",";
                }
            }
        },
        .optional =>|o| Query = if(@typeInfo(o.child) == .@"struct") genInsertConflicts(o.child, name) else std.fmt.comptimePrint("{s}{s}=excluded.{s}", .{ Query, name, name }),
        inline  .int, .pointer, .@"enum" => Query = std.fmt.comptimePrint("{s}{s}=excluded.{s}", .{ Query, name, name }),
        else => |t| @compileLog(t),
    }
    Query = Query ++ "";
    return Query;
}

fn genInsertValues(comptime fieldType: type) []const u8 {
    var Query: []const u8 = "";
    switch (@typeInfo(fieldType)) {
        .@"struct" => |s| {
            if (Constraints.resolveProps(fieldType).hasPropsSet()) {
                Query = std.fmt.comptimePrint("{s}?", .{Query});
            } else {
                for (s.fields, 0..) |field, i| {
                    if (i > 0) Query = Query ++ " ";
                    Query = Query ++ genInsertValues(field.type);
                    if (i < s.fields.len - 1) Query = Query ++ ",";
                }
            }
        },
        .optional =>|o| Query = if(@typeInfo(o.child) == .@"struct") genInsertValues(o.child) else std.fmt.comptimePrint("{s}?", .{ Query }),
        inline .int, .pointer, .@"enum" => Query = std.fmt.comptimePrint("{s}?", .{Query}),
        else => |t| @compileLog(t),
    }
    Query = Query ++ "";
    return Query;
}
fn genInsertValuesForType(comptime fieldType: type, comptime name: []const u8, props: Constraints.PropFields) []const u8 {
    var Query: []const u8 = "";
    switch (@typeInfo(fieldType)) {
        .@"struct" => |s| {
            if (props.hasPropsSet()) {
                Query = std.fmt.comptimePrint("{s}{s}", .{ Query, name });
            } else {
                for (s.fields, 0..) |field, i| {
                    if (i > 0) Query = Query ++ " ";
                    Query = Query ++ genInsertValuesForType(field.type, name ++ "_" ++ field.name, Constraints.resolveProps(field.type));
                    if (i < s.fields.len - 1) Query = Query ++ ",";
                }
            }
        },
        .optional =>|o| Query = if(@typeInfo(o.child) == .@"struct") genInsertValuesForType(o.child, name, props) else std.fmt.comptimePrint("{s}{s}", .{ Query, name }),
        inline .int, .pointer, .@"enum" => Query = std.fmt.comptimePrint("{s}{s}", .{ Query, name }),
        else => |t| @compileLog(t, props, name),
    }
    Query = Query ++ "";
    return Query;
}

pub fn InsertStatement(comptime table: type, comptime name: []const u8) []const u8 {
    const QueryString = comptime blk: {
        var Query: []const u8 = "INSERT INTO " ++ name ++ "(";
        var primary: []const u8 = undefined;
        for (std.meta.fields(table), 0..) |field, i| {
            const props = Constraints.resolveProps(field.type);
            if (props.PrimaryKey) primary = field.name;
            if (i > 0) Query = Query ++ " ";
            Query = Query ++ genInsertValuesForType(field.type, field.name, props);
            if (i < std.meta.fields(table).len - 1) Query = Query ++ ",";
        }
        Query = Query ++ ")";
        Query = Query ++ " VALUES (";
        for (std.meta.fields(table), 0..) |field, i| {
            if (i > 0) Query = Query ++ " ";
            Query = std.fmt.comptimePrint("{s}{s}", .{ Query, genInsertValues(field.type) });
            if (i < std.meta.fields(table).len - 1) Query = Query ++ ",";
        }
        Query = Query ++ ") ON CONFLICT(" ++ primary ++ ") DO UPDATE SET";

        //Generate Conflicts
        for (std.meta.fields(table), 0..) |field, i| {
            if (std.mem.eql(u8, field.name, primary)) continue;
            if (i > 0) Query = Query ++ " ";
            Query = std.fmt.comptimePrint("{s}{s}", .{ Query, genInsertConflicts(field.type, field.name) });
            if (i < std.meta.fields(table).len - 1) Query = Query ++ ",";
        }
        Query = Query ++ ";";
        break :blk Query;
    };
    return QueryString;
}

fn genCreateForType(comptime ftype: type, comptime name: []const u8, comptime props: Constraints.PropFields, dv: ?ftype) []const u8 {
    var Query: []const u8 = "";
    switch (@typeInfo(ftype)) {
        .@"struct" => |s| {
            const ps = Constraints.resolveProps(ftype);
            if (ps.hasPropsSet()) {
                Query = Query ++ genCreateForType(@FieldType(ftype, "inner"), name, ps, if (dv) |dvu| dvu.get() else null);
            } else {
                for (s.fields, 0..) |field, i| {
                    Query = Query ++ genCreateForType(field.type, std.fmt.comptimePrint("{s}_{s}", .{ name, field.name }), .{}, field.defaultValue());
                    if (i < s.fields.len - 1) Query = Query ++ ", ";
                }
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
            Query = Query ++ genCreateForType(o.child, name, props, if (dv) |dvu| dvu else null);
        },
        .pointer => |p| {
            if (p.child == u8 and p.size == .slice) {
                Query = Query ++ name ++ " TEXT";
                const propArr = props.getSetProps();
                for (propArr) |prop| {
                    Query = std.fmt.comptimePrint("{s} {s}", .{ Query, Constraints.Props.Values[@intFromEnum(prop)] });
                }
                if (!props.PrimaryKey) {
                    if (dv) |dvu| Query = std.fmt.comptimePrint("{s} DEFAULT '{s}'", .{ Query, dvu });
                }
            } else {
                @compileError("Unimplemented");
            }
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
                    Query = Query ++ genCreateForType(f.type, f.name, .{}, f.defaultValue());
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
