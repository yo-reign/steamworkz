const std = @import("std");
const steam = @import("steamworkz");

// Retained for real native linkage in every mode; never called by pure main.
export fn consumerClientLoggedOn(client: *const steam.Client) bool {
    return client.loggedOn();
}

// Keep a reachable ownership transition so optimization cannot treat every
// lease as permanently closed and discard the native paths below.
export fn consumerInitialize(client: *steam.Client, diagnostic: *steam.Client.Diagnostic) bool {
    client.init(diagnostic) catch return false;
    return true;
}
export fn consumerShutdown(client: *steam.Client) void {
    client.deinit();
}

// Linkage coverage only, not an application recipe. Pure main never calls this
// function or changes global networking settings/registers a callback.
export fn consumerNetworking(client: *steam.Client, connection: u32, payload: [*]const u8, size: usize) bool {
    const net = client.networking();
    const handle: steam.Networking.Connection = @enumFromInt(connection);
    var lanes: [2]steam.Networking.LaneRealTimeStatus = undefined;
    const status = net.realTimeStatus(handle, &lanes) catch return false;
    std.mem.doNotOptimizeAway(status);
    var text: [256]u8 = undefined;
    const detail = net.detailedStatus(handle, &text) catch return false;
    std.mem.doNotOptimizeAway(detail);
    const configured = net.configureLanes(handle, &.{ .{ .priority = 0, .weight = 1 }, .{ .priority = 10, .weight = 1 } }) catch return false;
    std.mem.doNotOptimizeAway(configured);
    var outcomes: [1]steam.Networking.BatchSendOutcome = undefined;
    const sent = net.sendBatch(&.{.{ .connection = handle, .payload = payload[0..size], .lane = 1, .options = .{ .reliability = .reliable } }}, &outcomes) catch return false;
    std.mem.doNotOptimizeAway(sent);

    const config = client.networkingConfig();
    config.set(.global, .nagle_delay_us, 123) catch return false;
    const value = config.get(.global, .nagle_delay_us) catch return false;
    std.mem.doNotOptimizeAway(value);
    config.clear(.global, .nagle_delay_us) catch return false;
    const applied = config.applySimulation(.{ .send_lag_ms = 1 }) catch return false;
    std.mem.doNotOptimizeAway(applied);
    const reset = config.resetSimulation() catch return false;
    std.mem.doNotOptimizeAway(reset);

    const capture = client.networkingDebug();
    capture.start(.warning) catch return false;
    var records: [1]steam.NetworkingDebug.Record = undefined;
    std.mem.doNotOptimizeAway(capture.drain(&records));
    capture.stop() catch return false;
    return true;
}

// These M3 exports are linkage probes, not usage recipes. Pure main never
// invokes them: no keyboard, Input, stats, cloud or callback action runs here.
export fn consumerPlatformPoll(client: *steam.Client) void {
    client.runFrame();
    std.mem.doNotOptimizeAway(client.nextEvent());
}
export fn consumerUtils(client: *steam.Client) void {
    const utility = client.utils();
    std.mem.doNotOptimizeAway(utility.showGamepad(.{ .max_characters = 32 }));
    std.mem.doNotOptimizeAway(utility.dismissGamepad());
    std.mem.doNotOptimizeAway(utility.showFloating(.{ .x = -1, .y = 0, .width = 32, .height = 16 }));
    std.mem.doNotOptimizeAway(utility.dismissFloating());
    std.mem.doNotOptimizeAway(utility.initFilter());
    var output: [32]u8 = undefined;
    std.mem.doNotOptimizeAway(utility.filterText(.{ .context = .chat, .source = @enumFromInt(123) }, "text", &output));
    std.mem.doNotOptimizeAway(utility.defaultConfig());
}
export fn consumerInput(client: *steam.Client, handle: u64, manifest: [*:0]const u8) void {
    const controls = client.input();
    const controller: steam.Input.Controller = @enumFromInt(handle);
    const set: steam.Input.ActionSet = @enumFromInt(handle);
    const digital: steam.Input.DigitalAction = @enumFromInt(handle);
    const analog: steam.Input.AnalogAction = @enumFromInt(handle);
    std.mem.doNotOptimizeAway(controls.start(.{ .device_callbacks = true }));
    std.mem.doNotOptimizeAway(controls.runFrame());
    std.mem.doNotOptimizeAway(controls.setManifestPath(std.mem.span(manifest)));
    var controllers: [steam.Input.max_controllers]steam.Input.Controller = undefined;
    std.mem.doNotOptimizeAway(controls.connectedControllers(&controllers));
    std.mem.doNotOptimizeAway(controls.actionSet("action"));
    std.mem.doNotOptimizeAway(controls.digitalAction("action"));
    std.mem.doNotOptimizeAway(controls.analogAction("action"));
    std.mem.doNotOptimizeAway(controls.activateActionSet(controller, set));
    std.mem.doNotOptimizeAway(controls.activateLayer(controller, set));
    std.mem.doNotOptimizeAway(controls.deactivateLayer(controller, set));
    std.mem.doNotOptimizeAway(controls.deactivateAllLayers(controller));
    std.mem.doNotOptimizeAway(controls.currentActionSet(controller));
    var layers: [steam.Input.max_active_layers]steam.Input.ActionSet = undefined;
    std.mem.doNotOptimizeAway(controls.activeLayers(controller, &layers));
    std.mem.doNotOptimizeAway(controls.digitalData(controller, digital));
    std.mem.doNotOptimizeAway(controls.analogData(controller, analog));
    var origins: [steam.Input.max_origins]steam.Input.Origin = undefined;
    std.mem.doNotOptimizeAway(controls.digitalOrigins(controller, set, digital, &origins));
    std.mem.doNotOptimizeAway(controls.analogOrigins(controller, set, analog, &origins));
    std.mem.doNotOptimizeAway(controls.inputType(controller));
    std.mem.doNotOptimizeAway(controls.translateOrigin(.unknown, @enumFromInt(32767)));
    var text: [1024]u8 = undefined;
    std.mem.doNotOptimizeAway(controls.glyphPNG(.none, .large, .{}, &text));
    std.mem.doNotOptimizeAway(controls.glyphSVG(.none, .{}, &text));
    std.mem.doNotOptimizeAway(controls.originName(.none, &text));
    std.mem.doNotOptimizeAway(controls.digitalActionName(digital, &text));
    std.mem.doNotOptimizeAway(controls.analogActionName(analog, &text));
    std.mem.doNotOptimizeAway(controls.vibrate(controller, 1, 2));
    std.mem.doNotOptimizeAway(controls.vibrateExtended(controller, 1, 2, 3, 4));
    std.mem.doNotOptimizeAway(controls.stop());
}
export fn consumerCloud(client: *steam.Client, index: usize) void {
    const cloud = client.cloud();
    std.mem.doNotOptimizeAway(cloud.localChangeCount());
    var path: [1024]u8 = undefined;
    std.mem.doNotOptimizeAway(cloud.localChangeAt(index, &path));
    if (cloud.beginWriteBatch()) |acquired| {
        var batch = acquired;
        _ = batch.end() catch @panic("linkage probe must end its batch before close");
    } else |_| {}
}
export fn consumerProgression(client: *steam.Client, board_value: u64, previous: i32) void {
    const stats = client.stats();
    const board: steam.Leaderboard = @enumFromInt(board_value);
    std.mem.doNotOptimizeAway(stats.achievementIcon("achievement"));
    std.mem.doNotOptimizeAway(stats.findLeaderboard("leaderboard"));
    var name: [128]u8 = undefined;
    std.mem.doNotOptimizeAway(stats.leaderboardMetadata(board, &name));
    std.mem.doNotOptimizeAway(stats.downloadLeaderboard(board, .{ .global = .{ .first_rank = 1, .last_rank = 100 } }));
    std.mem.doNotOptimizeAway(stats.downloadLeaderboard(board, .{ .around_user = .{ .before = 10, .after = 20 } }));
    std.mem.doNotOptimizeAway(stats.downloadLeaderboardUsers(board, &.{@enumFromInt(board_value)}));
    std.mem.doNotOptimizeAway(stats.uploadLeaderboard(board, .{ .method = .force_update, .score = -77, .details = &.{ 1, -1 } }));
    std.mem.doNotOptimizeAway(stats.requestGlobalPercentages());
    std.mem.doNotOptimizeAway(stats.firstGlobalPercentage());
    std.mem.doNotOptimizeAway(stats.nextGlobalPercentage(@enumFromInt(previous)));
    std.mem.doNotOptimizeAway(stats.globalPercentage("achievement"));
}

// M4 linkage probes only. They remain uncalled. In particular, the screenshot
// probe does not provide a usable pending-storage policy or an application loop.
export fn consumerVoice(client: *steam.Client, compressed: [*]u8, bytes: usize, pcm: [*]i16, samples: usize) void {
    const voice = client.voice();
    std.mem.doNotOptimizeAway(voice.start());
    std.mem.doNotOptimizeAway(voice.state());
    std.mem.doNotOptimizeAway(voice.available());
    std.mem.doNotOptimizeAway(voice.stop());
    std.mem.doNotOptimizeAway(voice.read(compressed[0..bytes]));
    std.mem.doNotOptimizeAway(voice.optimalSampleRate());
    std.mem.doNotOptimizeAway(voice.decode(compressed[0..bytes], pcm[0..samples], 24000));
}
export fn consumerRemotePlay(client: *steam.Client, session_value: u32, friend_value: u64) void {
    const remote = client.remotePlay();
    const session: steam.RemotePlaySession = @enumFromInt(session_value);
    std.mem.doNotOptimizeAway(remote.sessionCount());
    std.mem.doNotOptimizeAway(remote.sessionAt(0));
    std.mem.doNotOptimizeAway(remote.isTogether(session));
    std.mem.doNotOptimizeAway(remote.steamId(session));
    std.mem.doNotOptimizeAway(remote.guestId(session));
    var name: [1024]u8 = undefined;
    std.mem.doNotOptimizeAway(remote.clientName(session, &name));
    std.mem.doNotOptimizeAway(remote.formFactor(session));
    std.mem.doNotOptimizeAway(remote.resolution(session));
    std.mem.doNotOptimizeAway(remote.showTogetherUi());
    std.mem.doNotOptimizeAway(remote.invite(.{ .friend = @enumFromInt(friend_value) }));
    std.mem.doNotOptimizeAway(remote.invite(.guest));
}
export fn consumerTimeline(client: *steam.Client, range: *steam.Timeline.Range, marker_value: u64) void {
    const timeline = client.timeline();
    const event: steam.Timeline.Event = .{ .title = "", .description = "", .icon = "", .priority = 0 };
    std.mem.doNotOptimizeAway(timeline.setMode(.playing));
    std.mem.doNotOptimizeAway(timeline.setTooltip("", 0));
    std.mem.doNotOptimizeAway(timeline.clearTooltip(0));
    std.mem.doNotOptimizeAway(timeline.instant(event, .{}));
    std.mem.doNotOptimizeAway(timeline.completed(event, .{}));
    std.mem.doNotOptimizeAway(timeline.remove(@enumFromInt(marker_value)));
    range.* = timeline.start(event, 0, .none) catch return;
}
export fn consumerTimelineRange(range: *const steam.Timeline.Range, finish: bool) void {
    std.mem.doNotOptimizeAway(range.update(.{ .title = "", .description = "", .icon = "", .priority = .keep_current, .clip = .none }));
    if (finish) std.mem.doNotOptimizeAway(range.end(0)) else std.mem.doNotOptimizeAway(range.cancel());
}
export fn consumerWorkshop(client: *steam.Client, item_value: u64, query: *steam.Workshop.Query) void {
    const workshop = client.workshop();
    const item: steam.WorkshopItem = @enumFromInt(item_value);
    std.mem.doNotOptimizeAway(workshop.subscriptionCount(.{}));
    var items: [4]steam.WorkshopItem = undefined;
    std.mem.doNotOptimizeAway(workshop.subscriptions(&items, .{}));
    std.mem.doNotOptimizeAway(workshop.itemState(item));
    var path: [1024]u8 = undefined;
    std.mem.doNotOptimizeAway(workshop.installInfo(item, &path));
    std.mem.doNotOptimizeAway(workshop.downloadProgress(item));
    std.mem.doNotOptimizeAway(workshop.downloadItem(item, .{}));
    query.* = workshop.createDetailsQuery(&.{item}) catch return;
    std.mem.doNotOptimizeAway(query.send());
}
export fn consumerWorkshopQuery(query: *const steam.Workshop.Query, index: u32, out: *steam.Workshop.Details) void {
    std.mem.doNotOptimizeAway(query.state());
    std.mem.doNotOptimizeAway(query.handle());
    std.mem.doNotOptimizeAway(query.resultCount());
    // A separate export keeps reads reachable after consumerPlatformPoll observes completion.
    std.mem.doNotOptimizeAway(query.read(index, out));
    std.mem.doNotOptimizeAway(query.release());
}
export fn consumerScreenshots(client: *steam.Client, rgb: [*]u8, bytes: usize, width: i32, height: i32, path: [*:0]const u8, thumbnail: ?[*:0]const u8) void {
    const screenshots = client.screenshots();
    std.mem.doNotOptimizeAway(screenshots.submitRgbBorrowed(rgb[0..bytes], width, height));
    std.mem.doNotOptimizeAway(screenshots.submitFile(std.mem.span(path), if (thumbnail) |value| std.mem.span(value) else null, width, height));
    std.mem.doNotOptimizeAway(screenshots.isHooked());
    std.mem.doNotOptimizeAway(screenshots.enableHook());
    std.mem.doNotOptimizeAway(screenshots.trigger());
    std.mem.doNotOptimizeAway(screenshots.disableHook());
}

pub fn main() !void {
    // Taking addresses retains production paths without executing them.
    std.mem.doNotOptimizeAway(&consumerClientLoggedOn);
    std.mem.doNotOptimizeAway(&consumerInitialize);
    std.mem.doNotOptimizeAway(&consumerShutdown);
    std.mem.doNotOptimizeAway(&consumerNetworking);
    std.mem.doNotOptimizeAway(&consumerPlatformPoll);
    std.mem.doNotOptimizeAway(&consumerUtils);
    std.mem.doNotOptimizeAway(&consumerInput);
    std.mem.doNotOptimizeAway(&consumerCloud);
    std.mem.doNotOptimizeAway(&consumerProgression);
    std.mem.doNotOptimizeAway(&consumerVoice);
    std.mem.doNotOptimizeAway(&consumerRemotePlay);
    std.mem.doNotOptimizeAway(&consumerTimeline);
    std.mem.doNotOptimizeAway(&consumerTimelineRange);
    std.mem.doNotOptimizeAway(&consumerWorkshop);
    std.mem.doNotOptimizeAway(&consumerWorkshopQuery);
    std.mem.doNotOptimizeAway(&consumerScreenshots);
    const query_identity: steam.WorkshopQuery = @enumFromInt(0);
    const screenshot_identity: steam.ScreenshotHandle = @enumFromInt(73);
    if (query_identity == .invalid or @intFromEnum(screenshot_identity) != 73) return error.ValueMismatch;
    const address = try steam.Networking.Address.parse("127.0.0.1:27015");
    var text: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer text.deinit();
    try address.format(&text.writer);
    if (!std.mem.eql(u8, text.written(), "127.0.0.1:27015")) return error.AddressMismatch;

    const image: steam.ImageHandle = @enumFromInt(37);
    const unknown: steam.Result = @enumFromInt(-12345);
    if (@intFromEnum(image) != 37 or @intFromEnum(unknown) != -12345) return error.ValueMismatch;
    var request = try steam.Request(.lobby_created).init(@enumFromInt(42));
    const event: steam.Event = .{
        .call = @enumFromInt(42),
        .callback_id = 513,
        .payload = .{ .lobby_created = .{ .lobby = @enumFromInt(123), .result = .access_denied } },
    };
    const value = (try request.take(&event)) orelse return error.MissingCompletion;
    if (value.result != .access_denied or @intFromEnum(value.lobby) != 123 or request.isPending()) return error.CompletionMismatch;
    if (try request.take(&event) != null) return error.DuplicateCompletion;
    inline for (.{ .lobby_entered, .lobby_list, .stats_received, .cloud_written, .leaderboard_found, .leaderboard_entries, .leaderboard_uploaded, .global_percentages_ready, .workshop_query_completed }) |kind| {
        const pending = try steam.Request(kind).init(@enumFromInt(99));
        if (!pending.isPending()) return error.MissingRequest;
    }
}
