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

//Helper function to resolve the properties;
pub inline fn resolveProps(comptime t: type) []Props {
    var prop_buffer: [16]Props = undefined;
    var count: u4 = 0;
    @setEvalBranchQuota(100000);
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

//Start of the Props Types
//-------------------------
pub fn NotNull(comptime inner: type) type {
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
pub fn PrimaryKey(comptime inner: type) type {
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

//Sets Unique on Conflict Replace
pub fn UniqueReplace(comptime inner: type) type {
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
