# Migration notes

These notes are for existing consumers; new projects should start with the [README](../README.md).

## Zig 0.17 migration

The game-facing API and ownership rules stay unchanged. The migration changes
compiler interfaces and build plumbing:

| Before | Zig 0.17 | Why |
| --- | --- | --- |
| Source `@cImport` blocks | Pinned `translate_c` 2.0.2 build dependency and `@import("steamworkz_c")` | C translation moved out of the compiler |
| `b.pathFromRoot(path)` | `b.pathResolve(&.{ b.fmt("{f}", .{b.root}), path })` | SDK paths stay relative to the owning project |
| `b.args` / `run.addArgs(args)` | `run.addPassthruArgs()` | Run arguments no longer belong to build configuration |
| `std.builtin.OptimizeMode`, `.ReleaseFast` | `std.lang.Optimize`, `.fast` | Optimization modes moved and use lowercase names |
| `@intFromEnum(value)` | `@backingInt(value)` | One operation reads enum and packed-struct backing integers |
| `@enumFromInt(raw)` | `@fromBackingInt(@intCast(raw))` | The result type determines the required backing integer type |
| `[_]u8{0} ** N` | `@as([N]u8, @splat(0))` | Array repetition is removed. The destination supplies the length |
| `std.meta.fields(T)` | `@typeInfo(T).@"struct".field_names` and `@FieldType(T, name)` | Reflection exposes names and types separately instead of field records |
| `allocator.dupeZ(u8, text)` | `allocator.dupeSentinel(u8, text, 0)` | Sentinel APIs now specify the sentinel explicitly |
| `std.fmt.bufPrintZ(buf, fmt, args)` | `std.mem.printSentinel(buf, fmt, args, 0)` | Buffer formatting moves to `std.mem` |
| `std.fmt.allocPrintSentinel(allocator, fmt, args, 0)` | `allocator.printSentinel(fmt, args, 0)` | Allocating formatting moves to the allocator |

`std.meta.declarations(T)` now returns declaration names directly. Private schema
checks use those names and `field_types` where only payload types are needed.
`zig fmt` performs enum-conversion and optimization-name migrations automatically.
The explicit `@intCast` preserves the backing-type conversion previously supplied
by `@enumFromInt`. Unknown enum values remain valid where the enum permits them.

The translator runs on the build host but emits declarations for the selected
target. It translates only Steamworkz-owned C headers. The C++ bridge still
compiles against the external official SDK. Generated bindings stay in the cache.
The lifecycle runner has separate target-aware libc imports. It retains Darwin's
POSIX feature selection and the Linux translation-only `_FORTIFY_SOURCE` override.
Release-mode lifecycle and owner-thread checks remain active.

Run-step APIs use `setName` and the explicit `add*Arg2(..., options)` variants.
The nested consumer invokes `.zig_exe`, not a compiler found through PATH.
Its cache paths resolve at execution time. `--pkg-dir` keeps extracted packages
outside relocated source, and `ZIG_GLOBAL_CACHE_DIR` selects the global cache.
Zig 0.17's `build` and `fetch` commands no longer accept `--global-cache-dir`.
The source checker uses fresh external caches and audits the actual fetched archive.

Linux keeps LLVM/LLD and explicit adjacent-runtime lookup. This migration does
not adopt a new linker, initialize Steam, run tutorials, or change SDK distribution.
Historical 0.16 results remain historical. Current validation belongs in
[CHECKPOINT.md](development/CHECKPOINT.md). See the
[Zig release notes](https://ziglang.org/download/0.17.0/release-notes.html) and
[official translator](https://codeberg.org/ziglang/translate-c) for upstream details.

## Migrating the initial API

The extracted baseline already includes the following changes from its initial
API. Extraction renames the dependency/module to `steamworkz` without changing
these signatures. Older callers may need these migrations:

| Initial API | Current API |
| --- | --- |
| `send(connection, bytes, flags)` | `send(connection, bytes, options)` or explicit `sendRaw` |
| Send result struct with `result` and `number` | `SendOutcome` with `accepted` or `rejected` |
| Positional close arguments | `close(connection, CloseOptions)` |
| `socketPair(bool)` | `socketPair(SocketPairOptions)` |
| Native mutation booleans in networking | Error unions handled with `try` or `catch` |
| Receive count and manual per-message cleanup | `MessageBatch`, `batch.messages`, and one `defer` |
| `lobbies.create(type, limit)` | `lobbies.create(.{ .visibility = type, .member_limit = limit })` |
| Raw call handles from create/join/search/stats/cloud requests | Typed `Request(kind)` and `take(&event)` |
| `Lobbies.Error.NativeFailure` | `OperationFailed`, `RequestRejected`, or `InvalidNativeResult`, according to the failure |
| `Friends.requestUser(user, bool)` | `Friends.requestUser(user, .{ .name_only = bool })` |
| Integer avatar image handles | `ImageHandle` |
| Integer relay availability in events | `Networking.Availability` |

Raw `ApiCall` values remain in events and each request's `call` field.
`Request.isPending()` distinguishes active and completed trackers.
Added event tags require updating exhaustive switches. The M3 `nextEvent` method
also requires `*Client` rather than `*const Client` for ownership transitions.
