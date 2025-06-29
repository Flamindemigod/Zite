# Zite
A small *binding* library that's mostly about centered around using Zig Structures,
directly instead of writing your own SQL but still gives you the option to write your own.

> [!WARNING]
> <p> The library is mostly a proof of concept at the moment.<br>
> <sub>Will slowly be refining it as i write my own projects that depend on it.</sub></p>

## Dependencies
- [Zig - v0.14.0](https://ziglang.org/download/#release-0.14.1)
- libc

## Quick Start
### Installation
<details>
<summary><h5>With Zig Fetch</h5></summary>
  
```console
$ zig fetch --save git+https://github.com/flamindemigod/zite.git
```

```zig
//build.zig
const Zite = b.dependency("Zite", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("Zite", Zite.module("Zite"));
```
</details>

<details>
<summary><h5>With Git Submodule</h5></summary>
  
```console
$ git submodule add git@github.com:Flamindemigod/Zite.git ./vendored/Zite
```

```.zig.zon
//build.zig.zon
.dependencies = .{
  .Zite = .{
    .path = "./vendored/Zite",
  },
},
```

```zig
//build.zig
const Zite = b.dependency("Zite", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("Zite", Zite.module("Zite"));
```
</details>

### Usage
```zig
//Init the DB
//This opens the DB, and sets up the arena allocator that it
//uses internally for small allocations as part of the exec process
var db = try Zite.init(allocator, "Test.db", &.{ .create, .readwrite });
//Rememeber to defer deinit
//Closes the db and also just cleans up the allocator
defer db.deinit();

...

//Generates the Create Statement
//Giving the function the type of the table and name it'll generate a ``CREATE`` stmt
//You can modify the statements at comptime if you need some specific stuff added onto it.
//fn TableToCreateStatement(comptime table: type, comptime name: []const u8) []const u8
const stmt = comptime Zite.Utils.TableToCreateStatement(DBUser, "User");

//And then we exec the stamenent
//if you give exec a return type it'll try to return a arraylist of that data.
//Mostly just useful if you're using ``SELECT`` otherwise you can leave it as void
//and discard the result since its going to be null or a better way of doing it would be
//fn exec(self: *Zite, comptime RetType: type, stmt: []const u8) !?std.ArrayList(RetType)
try db.exec(void, stmt) orelse unreachable;

...

//Inserting Data into the DB
//fn InsertStatement(comptime table: type, comptime name: []const u8) []const u8
//Same with TableToCreateStatement, this function generates a ``INSERT`` statement
//depending on the type provided, You also got to provide the name of the table as well.
const stmt = comptime Zite.Utils.InsertStatement(DBUser, "User");
//Bind and exec is a special function that traverses the structure of the data and inserts the data in
//This is very dependendent on order. the type of data doesnt need to be the same as type used to
//generate the statement. Its a pretty unsafe way of doing this. I do plan on adding more checks later on.
//But for now i would suggest using the same data structure for both the data and for generating the statement.
//Or you can look at the simple example where i generate a structure at comptime based on another structure
//and tack on a field for the key
//fn bindAndExec(self: *Zite, comptime stmt: []const u8, value: anytype) !void
try db.bindAndExec(stmt, data);

...

//You can also just write your own SQL for SELECT Staments. I might consider bind and exec returning data as well
//But for now its just exec that is able to return data.
//fn exec(self: *Zite, comptime RetType: type, stmt: []const u8) !?std.ArrayList(RetType)
var ret = try db.exec(test_struct, "SELECT * FROM Main;") orelse unreachable;
defer ret.deinit();
```
### Funny Type System Abuse
<details><summary><h5>Yap. Ignore if you dont wanna cringe</h5></summary>
  
So in my pursuit of a ergonomic way to interface between zig and sqlite i had a idea.
What if you could annotate fields like you can in rust using [attribute macros](https://doc.rust-lang.org/reference/procedural-macros.html#r-macro.proc.attribute)
```rust
  struct KV<T>{
    #[PrimaryKey]
    key: usize,
    value: T,
  }
```
Sadly, zig doesnt allow you to do anything funky like that. However while i was messing around with generics, 
I noticed that the type names are based on the function if you return anonymous structs.
[So I began blasting](https://www.youtube.com/watch?v=AHzw4QvE2Do),

```zig
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
```
The code above is a early prototype of Annotating the Fields with meta info, Which allowed you to do this
```zig
const KV = struct {
  key: PrimaryKey(usize),
  value: u32,
};
```
And shockingly it worked. If you ran @typeName on that type. It would be something like PrimaryKey(usize), 
and if you chained it with even more stuff it would basically append the names. Even though the underlying structure is
```zig
  struct {
    inner: InnerType
  }
```
with a getter and setter. 
So after a bunch of itterations i ended up with [this](https://github.com/Flamindemigod/Zite/blob/ea1e5727e1102f7034b24a1eac0a287bac14667a/src/Constraints.zig#L87C1-L114C2).
Which basically is a more "refined" way of handling it, since it doesnt require a insane amount of code duplication,
like i had before.
</details>

Within Zite there is a Constraints Module, that exports a few "helper functions". 
With them you can do something like 
```zig
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
```
If you care about what those functions are doing, I'd suggest reading the yap above.
TLDR. those functions return a struct that has 2 functions defined on it. 
- A `set` function that accepts the inner value
- A `get` function that returns the inner value
And using the entire structure to generate the statements will cause those fields to be annotated

## Contributing
<p>
Currently I'm the only person working on Zite as its mostly a personal project. 
However feel free to make bug reports or make pull requests if you'd like, 
If you want to contribute code then first make a issue with what you'd like to do.
I don't want to waste your time by rejecting pull requests because it doesnt align with my vision of the project. 
It doesnt stop you from forking the project and making changes, as long as its within the license.

As for LLMs, i'd suggest looking at <a href="https://www.brainmade.org">Brainmade</a>.
</p>
<br>
<div >
  <a href="https://brainmade.org/"><img src ="https://brainmade.org/black-logo.svg"/></a>
</div>

