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

pub fn TableToCreateStatement(comptime table: type, comptime name: []const u8) []const u8 {
    const QueryString = comptime blk: {
        var Query: []const u8 = "CREATE TABLE IF NOT EXISTS " ++ name ++ "(";
        switch (@typeInfo(table)) {
            .@"struct" => |s| {
                for (s.fields, 0..) |f, i| {
                    switch (@typeInfo(f.type)) {
                        .@"struct" => {
                            const props = Constraints.resolveProps(f.type);
                            if (props.getSetProps().len != 0) {
                                Query = Query ++ f.name;
                                switch (@typeInfo(@FieldType(f.type, "inner"))) {
                                    .int => {Query = Query ++ " INTEGER ";
                                const propArr = props.getSetProps();
                                for (propArr, 0..) |prop, pi| {
                                    Query = Query ++ Constraints.Props.Values[@intFromEnum(prop)];
                                    if (pi < propArr.len - 1) Query = Query ++ " ";
                                }
                                if(!props.PrimaryKey) {if(f.defaultValue())|dv| Query = Query ++ " DEFAULT " ++ std.fmt.comptimePrint("{d}", .{dv.get()});}
                                    },
                                    .@"enum" =>{
                                        Query = Query ++ " INTEGER ";
                                const propArr = props.getSetProps();
                                for (propArr, 0..) |prop, pi| {
                                    Query = Query ++ Constraints.Props.Values[@intFromEnum(prop)];
                                    if (pi < propArr.len - 1) Query = Query ++ " ";
                                }
                                if(!props.PrimaryKey) {if(f.defaultValue())|dv| Query = Query ++ " DEFAULT " ++ std.fmt.comptimePrint("{d}", .{@intFromEnum(dv.get())});}
                                    },
                                    else => |t| @compileLog(t),
                                }
                            }
                        },
                        .int => {
                            Query = Query ++ f.name ++ " INTEGER";
                            if(f.defaultValue())|dv| Query = Query ++ " DEFAULT " ++ std.fmt.comptimePrint("{d}", .{dv});
                        },
                        .@"enum" => {
                            Query = Query ++ f.name ++ " INTEGER";
                            if(f.defaultValue())|dv| Query = Query ++ " DEFAULT " ++ std.fmt.comptimePrint("{d}", .{@intFromEnum(dv)});
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
    return QueryString;
}
