const std = @import("std");
const common = @import("common.zig");

const log = std.log.scoped(.web_search);

pub fn execute(
    allocator: std.mem.Allocator,
    query: []const u8,
    count: usize,
    api_key: []const u8,
    timeout_secs: u64,
) (common.ProviderSearchError || error{OutOfMemory})!common.ToolResult {
    const timeout_str = try common.timeoutToString(allocator, timeout_secs);
    defer allocator.free(timeout_str);

    const endpoint = "https://api.exa.ai/search";
    const key_header = try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{api_key});
    defer allocator.free(key_header);

    const payload = .{
        .query = query,
        .numResults = count,
    };
    const body_json = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(body_json);
    log.info("exa request body_len={d}", .{body_json.len});

    const headers = [_][]const u8{
        key_header,
        "Accept: application/json",
    };

    const body = common.curlPostJson(allocator, endpoint, body_json, &headers, timeout_str) catch |err| {
        common.logRequestError("exa", query, err);
        return err;
    };
    defer allocator.free(body);

    var parsed = common.parseJsonObject(allocator, body) catch |err| {
        if (err == error.InvalidResponse) {
            const preview_len = @min(body.len, 160);
            log.err("exa InvalidResponse body_preview={s}", .{body[0..preview_len]});
        }
        return err;
    };
    defer parsed.deinit();

    const results_arr = common.requireArrayField(parsed.object, "results") catch |err| {
        if (err == error.InvalidResponse) {
            const preview_len = @min(body.len, 160);
            log.err("exa missing results array body_preview={s}", .{body[0..preview_len]});
        }
        return err;
    };
    return common.formatResultsArray(allocator, results_arr, query, "summary", "text");
}

test "exa payload stringify is a json object" {
    const payload = .{
        .query = "nnu",
        .numResults = @as(usize, 3),
    };
    const body = try std.json.Stringify.valueAlloc(std.testing.allocator, payload, .{});
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.startsWith(u8, body, "{"));
    try std.testing.expect(std.mem.indexOf(u8, body, "\"query\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"numResults\"") != null);
}
