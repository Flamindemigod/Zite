//A Small subset of Constraints that exist within SQLITE3
//Not all of them can be made like this
//but it holds atleast some.
//Making a more generic system kinda requires a lot more work
//and not entirely sold that it would work as intended.
//So for now the workflow im intending to use instead is to
//Generate the String at compile time and then modify it at runtime
//for whatever else you need thats not trivial to implement in this module
//All the Function bodies are exactly the same. the only diffrence is the Name
//This is because we abuse the fact that the type system cannot compress the types
//when the functions return a anonymous struct. So we end up with types that look like `NotNull(UniqueReplace(PrimaryKey(u8)))`
//but are internally just struct {inner: u8}; with 2 functions attached to it to unwrap and set the values easily.

const std = @import("std");

//List of props and Values that basically get injected into the statement
pub const Props = enum {
    PrimaryKey,
    UniqueReplace,
    NotNull,
    pub const Values: []const []const u8 = &.{
        "PRIMARY KEY",
        "UNIQUE ON CONFLICT REPLACE",
        "NOT NULL ON CONFLICT FAIL",
    };
};

pub const PropFields = packed struct {
    PrimaryKey: bool = false,
    UniqueReplace: bool = false,
    NotNull: bool = false,
    reserved: bool = false,

    pub fn hasPropsSet(comptime self: *const PropFields) bool {
        return (@as(u4, @bitCast(self.*)) & 1) != 0;
    }

    pub fn getSetProps(comptime self: *const PropFields) []Props {
        var props: [std.meta.fields(Props).len]Props = undefined;
        var count = 0;
        for (std.meta.fields(Props)) |field| {
            if (@as(u4, @bitCast(self.*)) & (1 << field.value) != 0) {
                props[count] = @as(Props, @enumFromInt(field.value));
                count += 1;
            }
        }
        return props[0..count];
    }
};
//Helper function to resolve the properties;

pub inline fn resolveProps(comptime t: type) PropFields {
    var prop_buffer: PropFields = .{};
    switch (@typeInfo(t)) {
        .int => {},
        .@"struct" => |s| if (@hasField(t, "inner") and @hasField(t, "props")) {
            prop_buffer = @bitCast(s.fields[1].defaultValue().?);
        },
        .@"enum" => {},
        else => |e| @compileLog(e),
    }
    return prop_buffer;
}

//Start of the Props Types
//-------------------------

fn NewPropFields(comptime old: type, comptime Property: Props) type {
    var PropF = @typeInfo(old);
    var fields: [PropF.@"struct".fields.len]std.builtin.Type.StructField = undefined;
    for (PropF.@"struct".fields, 0..) |field, i| {
        if (std.mem.eql(u8, @tagName(Property), field.name)) {
            var newF = field;
            newF.default_value_ptr = &true;
            fields[i] = newF;
        } else {
            fields[i] = field;
        }
    }
    PropF.@"struct".fields = &fields;
    PropF.@"struct".decls = &.{};
    return @Type(PropF);
}

fn SetProp(comptime inner: type, comptime Prop: Props) type {
    const p = resolveProps(inner);
    if (!p.hasPropsSet()) {
        return struct {
            inner: inner,
            props: NewPropFields(PropFields, Prop) = .{},
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
            props: NewPropFields(@FieldType(inner, "props"), Prop) = .{},
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

pub fn NotNull(comptime inner: type) type {
    return SetProp(inner, .NotNull);
}

pub fn PrimaryKey(comptime inner: type) type {
    return SetProp(inner, .PrimaryKey);
}

pub fn UniqueReplace(comptime inner: type) type {
    return SetProp(inner, .UniqueReplace);
}
