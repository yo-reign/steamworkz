//! Borrowed owner-thread voice facade. Construction does nothing. Start and
//! stop are explicit; after stop, keep reading until NotRecording to drain the
//! native tail. Session close discards any remaining tail without waiting.
//! No playback, transmission, arbitrary-PCM encoding or audio thread is owned.
//! Voice methods belong to ISteamUser, not a separate voice interface:
//! https://partner.steamgames.com/doc/api/ISteamUser
const std = @import("std");
const Context = @import("Context.zig");
const c = @cImport({
    @cInclude("voice.h");
});
const native = if (@import("builtin").is_test) TestApi else c;
const Voice = @This();

lease: Context.Lease,

pub const State = @FieldType(Context, "voice_state");
pub const Result = enum(i32) {
    ok = 0,
    not_initialized = 1,
    not_recording = 2,
    no_data = 3,
    buffer_too_small = 4,
    data_corrupted = 5,
    restricted = 6,
    unsupported_codec = 7,
    receiver_out_of_date = 8,
    receiver_did_not_answer = 9,
    _,
};
pub const Error = error{ InterfaceUnavailable, AlreadyRecording, Draining, InvalidSampleRate, InvalidSize, OverlappingBuffers };
pub const StopOutcome = enum { draining, inactive, already_draining };
pub const Available = struct { result: Result, compressed_bytes: u32 };
/// Raw counts survive native failure and malformed OK output. Data borrows
/// caller storage and exists only for OK with valid bounds. Even native failure
/// may mutate that storage. malformed_count distinguishes invalid OK output
/// from a native error; it never represents a successful clamped slice.
pub const Compressed = struct {
    result: Result,
    bytes_written: u32,
    data: ?[]u8,
    malformed_count: bool,
};
/// Mono signed 16-bit PCM. bytes_written is bytes, not samples; data.len counts
/// samples. The same borrowing/failure rules as Compressed apply.
pub const Decoded = struct {
    result: Result,
    bytes_written: u32,
    data: ?[]i16,
    malformed_count: bool,
};

/// ISteamUser::StartVoiceRecording explicitly enables microphone capture.
/// Returns void natively: invocation, not microphone readiness.
pub fn start(self: Voice) Error!void {
    self.lease.check();
    switch (self.lease.context.voice_state) {
        .recording => return error.AlreadyRecording,
        .draining => return error.Draining,
        .inactive => {},
    }
    try status(native.sw_voice_start());
    self.lease.context.voice_state = .recording;
}
/// A recording stop invokes native stop once and enters draining. No-op states
/// perform no interface lookup. Missing interfaces leave state unchanged.
pub fn stop(self: Voice) Error!StopOutcome {
    self.lease.check();
    switch (self.lease.context.voice_state) {
        .inactive => return .inactive,
        .draining => return .already_draining,
        .recording => {},
    }
    try status(native.sw_voice_stop());
    self.lease.context.voice_state = .draining;
    return .draining;
}
/// Wrapper recording/draining state, not a device or native readiness query.
pub fn state(self: Voice) State {
    self.lease.check();
    return self.lease.context.voice_state;
}
/// Client-only hook before native session shutdown, with a still-live lease.
/// At most one stop attempt, only while recording. No drain, wait, retry or
/// tail-delivery guarantee. Clears state even if the interface is unavailable.
pub fn shutdown(lease: Context.Lease) void {
    lease.check();
    if (lease.context.voice_state == .recording) _ = native.sw_voice_stop();
    lease.context.voice_state = .inactive;
}
/// ISteamUser::GetAvailableVoice queries compressed byte availability.
/// A snapshot, not a promise that a later read will fill this many bytes.
/// NotRecording here does not complete draining; only read can do that.
pub fn available(self: Voice) Error!Available {
    self.lease.check();
    var result: i32 = 0;
    var bytes: u32 = 0;
    try status(native.sw_voice_available(&result, &bytes));
    return .{ .result = @enumFromInt(result), .compressed_bytes = bytes };
}
/// ISteamUser::GetVoice reads compressed data only. Inspect result and
/// malformed_count before using data. Explicit read in any state, including
/// inactive. NoData does not finish draining; only NotRecording does.
pub fn read(self: Voice, destination: []u8) Error!Compressed {
    self.lease.check();
    const capacity = try byteCount(destination.len);
    var result: i32 = 0;
    var bytes: u32 = 0;
    try status(native.sw_voice_read(destination.ptr, capacity, &result, &bytes));
    const value: Result = @enumFromInt(result);
    if (value == .not_recording) self.lease.context.voice_state = .inactive;
    const malformed = value == .ok and bytes > capacity;
    return .{
        .result = value,
        .bytes_written = bytes,
        .data = if (value == .ok and !malformed) destination[0..bytes] else null,
        .malformed_count = malformed,
    };
}
/// ISteamUser::DecompressVoice into caller-owned mono PCM at 11025..48000 Hz.
/// Inspect result and malformed_count before using data. Input and
/// output must not overlap. Native failure may still modify destination.
pub fn decode(self: Voice, compressed: []const u8, destination: []i16, sample_rate: u32) Error!Decoded {
    self.lease.check();
    if (sample_rate < 11025 or sample_rate > 48000) return error.InvalidSampleRate;
    const input_bytes = try byteCount(compressed.len);
    const capacity = try pcmCapacity(destination.len);
    if (overlap(@intFromPtr(compressed.ptr), compressed.len, @intFromPtr(destination.ptr), capacity)) return error.OverlappingBuffers;
    var result: i32 = 0;
    var bytes: u32 = 0;
    try status(native.sw_voice_decode(compressed.ptr, input_bytes, destination.ptr, capacity, sample_rate, &result, &bytes));
    const value: Result = @enumFromInt(result);
    const malformed = value == .ok and (bytes > capacity or bytes % @sizeOf(i16) != 0);
    return .{
        .result = value,
        .bytes_written = bytes,
        .data = if (value == .ok and !malformed) destination[0 .. bytes / @sizeOf(i16)] else null,
        .malformed_count = malformed,
    };
}
/// Uncached native decoder rate, not a device-readiness flag.
pub fn optimalSampleRate(self: Voice) Error!u32 {
    self.lease.check();
    var rate: u32 = 0;
    try status(native.sw_voice_optimal_sample_rate(&rate));
    return rate;
}
fn status(value: i32) Error!void {
    if (value != 0) return error.InterfaceUnavailable;
}
fn byteCount(value: usize) Error!u32 {
    return std.math.cast(u32, value) orelse error.InvalidSize;
}
fn pcmCapacity(samples: usize) Error!u32 {
    const bytes = std.math.mul(usize, samples, @sizeOf(i16)) catch return error.InvalidSize;
    return byteCount(bytes);
}
fn overlap(a: usize, a_len: usize, b: usize, b_len: usize) bool {
    if (a_len == 0 or b_len == 0) return false;
    // Subtraction avoids overflow from computing either end pointer.
    return if (a <= b) b - a < a_len else a - b < b_len;
}

const TestApi = struct {
    var present = true;
    var calls: usize = 0;
    var starts: usize = 0;
    var stops: usize = 0;
    var result: i32 = 0;
    var count: u32 = 0;
    var rate: u32 = 24000;
    var last_rate: u32 = 0;
    var last_input_size: u32 = 0;
    var last_capacity: u32 = 0;
    fn reset() void {
        present = true;
        calls = 0;
        starts = 0;
        stops = 0;
        result = 0;
        count = 0;
        rate = 24000;
        last_rate = 0;
        last_input_size = 0;
        last_capacity = 0;
    }
    fn lookup() i32 {
        calls += 1;
        return if (present) 0 else -1;
    }
    fn sw_voice_start() i32 {
        const value = lookup();
        if (value == 0) starts += 1;
        return value;
    }
    fn sw_voice_stop() i32 {
        const value = lookup();
        if (value == 0) stops += 1;
        return value;
    }
    fn sw_voice_available(out_result: *i32, bytes: *u32) i32 {
        std.debug.assert(bytes.* == 0);
        const value = lookup();
        if (value == 0) {
            out_result.* = result;
            bytes.* = count;
        }
        return value;
    }
    fn sw_voice_read(out: [*]u8, capacity: u32, out_result: *i32, bytes: *u32) i32 {
        last_capacity = capacity;
        const value = sw_voice_available(out_result, bytes);
        if (value == 0 and capacity != 0) out[0] = 0x7b;
        return value;
    }
    fn sw_voice_decode(input: [*]const u8, input_size: u32, out: [*]i16, capacity: u32, sample_rate: u32, out_result: *i32, bytes: *u32) i32 {
        _ = input;
        last_input_size = input_size;
        last_rate = sample_rate;
        return sw_voice_read(@ptrCast(out), capacity, out_result, bytes);
    }
    fn sw_voice_optimal_sample_rate(out: *u32) i32 {
        const value = lookup();
        if (value == 0) out.* = rate;
        return value;
    }
};

test "Voice lifecycle shares copied state and drains only on read NotRecording" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    TestApi.reset();
    defer TestApi.reset();
    const voice: Voice = .{ .lease = context.lease() };
    const copy = voice;
    defer shutdown(voice.lease);
    var out: [4]u8 = undefined;
    try std.testing.expectEqual(.inactive, voice.state());
    try std.testing.expectEqual(.inactive, try voice.stop());
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    try voice.start();
    try std.testing.expectEqual(.recording, copy.state());
    try std.testing.expectError(error.AlreadyRecording, copy.start());
    try std.testing.expectEqual(.draining, try copy.stop());
    try std.testing.expectEqual(.already_draining, try voice.stop());
    try std.testing.expectError(error.Draining, voice.start());
    try std.testing.expectEqual(@as(usize, 2), TestApi.calls);
    TestApi.result = @intFromEnum(Result.no_data);
    try std.testing.expectEqual(Result.no_data, (try voice.read(&out)).result);
    try std.testing.expectEqual(.draining, copy.state());
    TestApi.result = @intFromEnum(Result.not_recording);
    try std.testing.expectEqual(Result.not_recording, (try copy.available()).result);
    try std.testing.expectEqual(.draining, voice.state());
    try std.testing.expectEqual(Result.not_recording, (try copy.read(&out)).result);
    try std.testing.expectEqual(.inactive, voice.state());
    try std.testing.expectEqual(@as(usize, 1), TestApi.starts);
    _ = try voice.read(&out); // Inactive reads remain explicit native operations.
    try voice.start();
    try std.testing.expectEqual(@as(usize, 2), TestApi.starts);
}

test "Voice missing interface preserves explicit lifecycle and returns no native result" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    TestApi.reset();
    defer TestApi.reset();
    const voice: Voice = .{ .lease = context.lease() };
    defer shutdown(voice.lease);
    var out: [4]u8 = undefined;
    var pcm: [4]i16 = undefined;
    TestApi.present = false;
    try std.testing.expectError(error.InterfaceUnavailable, voice.start());
    try std.testing.expectEqual(.inactive, voice.state());
    TestApi.present = true;
    try voice.start();
    TestApi.present = false;
    try std.testing.expectError(error.InterfaceUnavailable, voice.stop());
    try std.testing.expectEqual(.recording, voice.state());
    try std.testing.expectError(error.InterfaceUnavailable, voice.available());
    try std.testing.expectError(error.InterfaceUnavailable, voice.read(&out));
    try std.testing.expectError(error.InterfaceUnavailable, voice.decode(&out, &pcm, 24000));
    try std.testing.expectError(error.InterfaceUnavailable, voice.optimalSampleRate());
    try std.testing.expectEqual(.recording, voice.state());
}

test "Voice raw counts and unknown results never publish native failures or malformed OK" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    TestApi.reset();
    defer TestApi.reset();
    const voice: Voice = .{ .lease = context.lease() };
    var out: [4]u8 = @splat(0);
    var pcm: [4]i16 = @splat(0);
    for ([_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, std.math.minInt(i32), std.math.maxInt(i32) }) |result| {
        TestApi.result = result;
        TestApi.count = std.math.maxInt(u32);
        out[0] = 0;
        pcm[0] = 0;
        const available_bytes = try voice.available();
        const compressed = try voice.read(&out);
        const decoded = try voice.decode(&out, &pcm, 24000);
        try std.testing.expectEqual(result, @intFromEnum(available_bytes.result));
        try std.testing.expectEqual(TestApi.count, available_bytes.compressed_bytes);
        try std.testing.expectEqual(result, @intFromEnum(compressed.result));
        try std.testing.expectEqual(result, @intFromEnum(decoded.result));
        try std.testing.expectEqual(TestApi.count, compressed.bytes_written);
        try std.testing.expectEqual(TestApi.count, decoded.bytes_written);
        try std.testing.expect(compressed.data == null and decoded.data == null);
        try std.testing.expect(!compressed.malformed_count and !decoded.malformed_count);
        try std.testing.expectEqual(@as(u8, 0x7b), out[0]);
        try std.testing.expectEqual(@as(u8, 0x7b), std.mem.sliceAsBytes(&pcm)[0]);
    }
    TestApi.result = 0;
    for ([_]u32{ 0, 2, 3, 4, 5, 8, 9, std.math.maxInt(u32) }) |count| {
        TestApi.count = count;
        const compressed = try voice.read(&out);
        const decoded = try voice.decode(&out, &pcm, 24000);
        try std.testing.expectEqual(count, compressed.bytes_written);
        try std.testing.expectEqual(count, decoded.bytes_written);
        try std.testing.expectEqual(count > out.len, compressed.malformed_count);
        try std.testing.expectEqual(count > @sizeOf(@TypeOf(pcm)) or count % 2 != 0, decoded.malformed_count);
        if (compressed.data) |data| {
            try std.testing.expectEqual(count, data.len);
            try std.testing.expectEqual(out[0..].ptr, data.ptr);
        } else try std.testing.expect(compressed.malformed_count);
        if (decoded.data) |data| {
            try std.testing.expectEqual(count / 2, data.len);
            try std.testing.expectEqual(pcm[0..].ptr, data.ptr);
        } else try std.testing.expect(decoded.malformed_count);
    }
}

test "Voice validates byte arithmetic rates and overlap before native access" {
    var context: Context = undefined;
    try context.claim();
    defer context.release();
    TestApi.reset();
    defer TestApi.reset();
    const voice: Voice = .{ .lease = context.lease() };
    var pcm: [4]i16 = @splat(0);
    const input = "abc";
    for ([_]u32{ 0, 11024, 48001, std.math.maxInt(u32) }) |rate| {
        try std.testing.expectError(error.InvalidSampleRate, voice.decode(input, &pcm, rate));
    }
    const bytes = std.mem.sliceAsBytes(&pcm);
    try std.testing.expectError(error.OverlappingBuffers, voice.decode(bytes, &pcm, 24000));
    try std.testing.expectError(error.OverlappingBuffers, voice.decode(bytes[2..], pcm[0..2], 24000));
    try std.testing.expectError(error.OverlappingBuffers, voice.decode(bytes[0..4], pcm[1..], 24000));
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    try std.testing.expectError(error.InvalidSize, pcmCapacity(std.math.maxInt(usize)));
    try std.testing.expectError(error.InvalidSize, pcmCapacity(std.math.maxInt(u32) / 2 + 1));
    if (@sizeOf(usize) > @sizeOf(u32)) try std.testing.expectError(error.InvalidSize, byteCount(@as(usize, std.math.maxInt(u32)) + 1));
    try std.testing.expectEqual(std.math.maxInt(u32), try byteCount(std.math.maxInt(u32)));
    try std.testing.expect(!overlap(100, 4, 104, 2));
    try std.testing.expect(!overlap(104, 2, 100, 4));
    try std.testing.expect(!overlap(100, 0, 100, 4));
    try std.testing.expect(overlap(std.math.maxInt(usize) - 3, 4, std.math.maxInt(usize) - 1, 1));
    for ([_]u32{ 11025, 48000 }) |rate| {
        _ = try voice.decode(input, &pcm, rate);
        try std.testing.expectEqual(rate, TestApi.last_rate);
        try std.testing.expectEqual(@as(u32, 3), TestApi.last_input_size);
        try std.testing.expectEqual(@as(u32, 8), TestApi.last_capacity);
    }
    _ = try voice.decode(bytes[0..2], pcm[1..], 24000); // Adjacent, not overlapping.
    _ = try voice.decode(bytes[0..0], &pcm, 24000);
    _ = try voice.decode(bytes, pcm[0..0], 24000);
    TestApi.rate = std.math.maxInt(u32);
    try std.testing.expectEqual(TestApi.rate, try voice.optimalSampleRate());
    TestApi.rate = 0;
    try std.testing.expectEqual(@as(u32, 0), try voice.optimalSampleRate());
}

test "Voice shutdown is bounded skips unused and draining and new claim resets state" {
    var context: Context = undefined;
    try context.claim();
    var claimed = true;
    defer if (claimed) context.release();
    TestApi.reset();
    defer TestApi.reset();
    var voice: Voice = .{ .lease = context.lease() };
    defer if (claimed) shutdown(voice.lease);
    shutdown(voice.lease);
    try std.testing.expectEqual(@as(usize, 0), TestApi.calls);
    try voice.start();
    shutdown(voice.lease);
    shutdown(voice.lease);
    try std.testing.expectEqual(@as(usize, 2), TestApi.calls);
    try std.testing.expectEqual(@as(usize, 1), TestApi.stops);
    try std.testing.expectEqual(.inactive, voice.state());
    try voice.start();
    _ = try voice.stop();
    const calls = TestApi.calls;
    shutdown(voice.lease);
    try std.testing.expectEqual(calls, TestApi.calls);
    try voice.start();
    TestApi.present = false;
    shutdown(voice.lease);
    shutdown(voice.lease);
    try std.testing.expectEqual(.inactive, voice.state());
    try std.testing.expectEqual(calls + 2, TestApi.calls);
    context.voice_state = .draining;
    context.release();
    claimed = false;
    // Replace the deferred facade lease before any assertion in the new claim.
    try context.claim();
    claimed = true;
    voice = .{ .lease = context.lease() };
    try std.testing.expectEqual(.inactive, voice.state());
}
