const std = @import("std");
pub const Constraints = @import("Constraints.zig");

pub fn TableToCreateStatement(comptime table: type, comptime name: []const u8) []const u8 {
    const QueryString = comptime blk: {
        var Query: []const u8 = "CREATE TABLE IF NOT EXISTS " ++ name ++ "(";
        switch (@typeInfo(table)) {
            .@"struct" => |s| {
                for (s.fields, 0..) |f, i| {
                    switch (@typeInfo(f.type)) {
                        .@"struct" => {
                            const props = Constraints.resolveProps(f.type);
                            if (props.len != 0) {
                                Query = Query ++ f.name;
                                switch (@typeInfo(@FieldType(f.type, "inner"))) {
                                    .int => Query = Query ++ " INTEGER ",
                                    else => |t| @compileLog(t),
                                }
                                for (props, 0..) |prop, pi| {
                                    Query = Query ++ Constraints.Props.Values[@intFromEnum(prop)];
                                    if (pi < props.len - 1) Query = Query ++ " ";
                                }
                            }
                        },
                        inline .int, .@"enum" => {
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
    return QueryString;
}
