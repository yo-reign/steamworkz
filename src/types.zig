const std = @import("std");

pub const SteamId = enum(u64) { invalid = 0, _ };
pub const AppId = enum(u32) { invalid = 0, spacewar = 480, _ };
pub const ApiCall = enum(u64) { invalid = 0, _ };
pub const AuthTicket = enum(u32) { invalid = 0, _ };
/// SDK image identifier, not a GPU texture or an owned image allocation.
pub const ImageHandle = enum(i32) { invalid = 0, _ };

/// Unknown Steam result values remain representable after an SDK update.
pub const Result = enum(i32) {
    none = 0,
    ok = 1,
    fail = 2,
    no_connection = 3,
    invalid_password = 5,
    invalid_parameter = 8,
    file_not_found = 9,
    busy = 10,
    invalid_state = 11,
    access_denied = 15,
    timeout = 16,
    limit_exceeded = 25,
    duplicate_request = 29,
    io_failure = 37,
    _,
};

/// Use for fixed SDK text fields. No read can pass the end of the array.
pub fn text(bytes: []const u8) []const u8 {
    return bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len];
}

/// Copy all text into caller storage, without a terminator or silent truncation.
/// A short buffer remains unchanged. The returned slice borrows the buffer.
pub fn copyText(buffer: []u8, value: []const u8) error{BufferTooSmall}![]u8 {
    if (buffer.len < value.len) return error.BufferTooSmall;
    const out = buffer[0..value.len];
    @memmove(out, value);
    return out;
}

/// Check the C API's signed byte/count limit before narrowing a Zig slice length.
pub fn count(length: usize) error{TooLarge}!c_int {
    return std.math.cast(c_int, length) orelse error.TooLarge;
}

test "fixed text supports missing terminators without reading outside the slice" {
    try std.testing.expectEqualStrings("name", text("name\x00suffix"));
    try std.testing.expectEqualStrings("unterminated", text("unterminated"));
    try std.testing.expectEqualStrings("", text(""));
}

test "text copies own their bytes and never truncate or modify a short buffer" {
    var source = [_]u8{ 'a', 'b', 'c' };
    var storage = [_]u8{'x'} ** 4;
    const copied = try copyText(&storage, &source);
    @memset(&source, 'z');
    try std.testing.expectEqualStrings("abc", copied);
    try std.testing.expectEqual(@as(u8, 'x'), storage[3]);
    try std.testing.expectError(error.BufferTooSmall, copyText(storage[0..2], "long"));
    try std.testing.expectEqualStrings("abcx", &storage);
    try std.testing.expectEqualStrings("", try copyText(storage[0..0], ""));
    try std.testing.expectEqualStrings("bc", try copyText(&storage, storage[1..3]));
}

test "C counts reject overflow and retain exact representable values" {
    try std.testing.expectEqual(@as(c_int, 17), try count(17));
    try std.testing.expectError(error.TooLarge, count(@as(usize, std.math.maxInt(c_int)) + 1));
}

test "unexposed SDK results stay unnamed rather than acquiring unrelated error tags" {
    // SDK 1.65: ShoppingCartNotFound and NotSettled, not invalid-handle/buffer errors.
    for ([_]i32{ 39, 100 }) |raw| {
        const result: Result = @enumFromInt(raw);
        try std.testing.expect(std.enums.tagName(Result, result) == null);
        try std.testing.expectEqual(raw, @intFromEnum(result));
    }
}

test "unknown native results retain their numeric value" {
    const value: Result = @enumFromInt(123456);
    try std.testing.expectEqual(@as(i32, 123456), @intFromEnum(value));
}

test "property text terminator positions and copy capacities" {
    for (0..33) |length| {
        for (0..length + 1) |terminator| {
            var source: [32]u8 = @splat('s');
            if (terminator < length) source[terminator] = 0;
            const value = text(source[0..length]);
            try std.testing.expectEqual(terminator, value.len);
            for (0..34) |capacity| {
                var storage: [35]u8 = @splat(0xa5);
                const buffer = storage[1 .. capacity + 1];
                if (capacity < value.len) {
                    try std.testing.expectError(error.BufferTooSmall, copyText(buffer, value));
                    try std.testing.expectEqualSlices(u8, &(@as([35]u8, @splat(0xa5))), &storage);
                } else {
                    const result = try copyText(buffer, value);
                    try std.testing.expectEqualSlices(u8, value, result);
                    try std.testing.expectEqual(buffer.ptr, result.ptr);
                    for (storage[1 + value.len ..]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
                }
                try std.testing.expectEqual(@as(u8, 0xa5), storage[0]);
            }
        }
    }
    // Both overlap directions obey memmove, not memcpy semantics.
    for (0..17) |length| {
        var storage: [34]u8 = undefined;
        for (&storage, 0..) |*byte, i| byte.* = @intCast(i);
        var expected: [17]u8 = undefined;
        @memcpy(expected[0..length], storage[0..length]);
        try std.testing.expectEqualSlices(u8, expected[0..length], try copyText(storage[1..], storage[0..length]));
        try std.testing.expectEqualSlices(u8, expected[0..length], try copyText(&storage, storage[1 .. length + 1]));
    }
}
