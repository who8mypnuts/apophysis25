pub const packages = struct {
    pub const @"N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAEp9UgBJ2n1eks3_3YZk3GCO1XOENazWaCO7ggM2" = struct {
        pub const build_root = "/home/stan/.cache/zig/p/N-V-__8AAEp9UgBJ2n1eks3_3YZk3GCO1XOENazWaCO7ggM2";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAJl1DwBezhYo_VE6f53mPVm00R-Fk28NPW7P14EQ" = struct {
        pub const build_root = "/home/stan/.cache/zig/p/N-V-__8AAJl1DwBezhYo_VE6f53mPVm00R-Fk28NPW7P14EQ";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"deps/raylib" = struct {
        pub const build_root = "/home/stan/Work/python/apophysis25/zig-src/deps/raylib";
        pub const build_zig = @import("deps/raylib");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "xcode_frameworks", "N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" },
            .{ "emsdk", "N-V-__8AAJl1DwBezhYo_VE6f53mPVm00R-Fk28NPW7P14EQ" },
            .{ "zemscripten", "zemscripten-0.2.0-dev-sRlDqApRAACspTbAZnuNKWIzfWzSYgYkb2nWAXZ-tqqt" },
        };
    };
    pub const @"deps/raylib-zig" = struct {
        pub const build_root = "/home/stan/Work/python/apophysis25/zig-src/deps/raylib-zig";
        pub const build_zig = @import("deps/raylib-zig");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "raylib", "deps/raylib" },
            .{ "raygui", "N-V-__8AAEp9UgBJ2n1eks3_3YZk3GCO1XOENazWaCO7ggM2" },
        };
    };
    pub const @"zemscripten-0.2.0-dev-sRlDqApRAACspTbAZnuNKWIzfWzSYgYkb2nWAXZ-tqqt" = struct {
        pub const build_root = "/home/stan/.cache/zig/p/zemscripten-0.2.0-dev-sRlDqApRAACspTbAZnuNKWIzfWzSYgYkb2nWAXZ-tqqt";
        pub const build_zig = @import("zemscripten-0.2.0-dev-sRlDqApRAACspTbAZnuNKWIzfWzSYgYkb2nWAXZ-tqqt");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "raylib-zig", "deps/raylib-zig" },
};
