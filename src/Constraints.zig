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
    Default, 
    pub const Values: []const []const u8 = &.{
        "PRIMARY KEY",
        "UNIQUE ON CONFLICT REPLACE",
        "NOT NULL ON CONFLICT FAIL",
        "DEFAULT",
    };
};

pub const PropFields = packed struct {
    PrimaryKey: bool = false,
    UniqueReplace: bool = false,
    NotNull: bool = false,
    Default: bool = false,

    pub fn hasPropsSet(comptime self: *const PropFields) bool{
        return (@as(u4, @bitCast(self.*)) & 1) != 0;
    }

    pub fn getSetProps(comptime self: *const PropFields) []Props {
        var props: [std.meta.fields(Props).len]Props = undefined;
        var count = 0;
        for (std.meta.fields(Props)) |field|{
            if(@as(u4, @bitCast(self.*)) & (1 << field.value) != 0) {
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
    @setEvalBranchQuota(10000);
    inline for (std.meta.fields(Props)) |v| {
        if (std.mem.containsAtLeast(u8, @typeName(t), 1, v.name)) {
                @field(prop_buffer, @tagName(@as(Props, @enumFromInt(v.value)))) = true;
        }
    }
    return prop_buffer;
}

//Start of the Props Types
//-------------------------
pub fn NotNull(comptime inner: type) type {
    const p = resolveProps(inner);
    if (!p.hasPropsSet()) {
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
pub fn PrimaryKey(comptime inner: type) type {
    const p = resolveProps(inner);
    if (!p.hasPropsSet()) {
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

//Sets Unique on Conflict Replace
pub fn UniqueReplace(comptime inner: type) type {
    const p = resolveProps(inner);
    if (!p.hasPropsSet()) {
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
