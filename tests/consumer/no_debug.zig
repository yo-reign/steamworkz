// Import the package, but never reference or start its diagnostic facade.
// The build retains the real native registration function only to check that
// its required Zig sink is present. This executable is compile/install-only.
const steam = @import("steamworkz");
comptime {
    _ = steam;
}
pub fn main() void {}
