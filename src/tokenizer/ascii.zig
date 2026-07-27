const std = @import("std");
const Tokenizer = @import("./tokenizer.zig");

const Token = Tokenizer.Token;

const AsciiTokenizer = @This();

reader: *std.Io.Reader,
line: u64 = 1,

const vtable = Tokenizer.VTable{
    .next = next,
};

pub fn init(reader: *std.Io.Reader) AsciiTokenizer {
    return .{ .reader = reader };
}

pub fn tokenizer(self: *AsciiTokenizer) Tokenizer {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

fn cast(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(@alignCast(ptr));
}

fn next(ptr: *anyopaque) Tokenizer.Error!?Tokenizer.Token {
    const self = cast(AsciiTokenizer, ptr);

    const code_line_no = self.line;
    const code_line = try self.take_line() orelse return null;
    const code = try parse_group_code(code_line);

    const value_line_no = self.line;
    const value_line = try self.take_line() orelse return error.MissingGroupValue;

    return .{
        .code = code,
        .value = .{ .raw = value_line },
        .loc = .{
            .code_line = code_line_no,
            .value_line = value_line_no,
        },
    };
}

fn take_line(self: *AsciiTokenizer) Tokenizer.Error!?[]const u8 {
    const line = self.reader.takeDelimiter('\n') catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.StreamTooLong => return error.LineTooLong,
    };

    const bytes = line orelse return null;
    self.line += 1;
    return trimCarriageReturn(bytes);
}

fn trimCarriageReturn(bytes: []const u8) []const u8 {
    if (bytes.len == 0) return bytes;
    if (bytes[bytes.len - 1] == '\r') return bytes[0 .. bytes.len - 1];
    return bytes;
}

fn parse_group_code(bytes: []const u8) Tokenizer.Error!i16 {
    const trimmed = std.mem.trim(u8, bytes, " \t\r");
    if (trimmed.len == 0) return error.InvalidGroupCode;

    return std.fmt.parseInt(i16, trimmed, 10) catch return error.InvalidGroupCode;
}

test "next returns ascii DXF tokens" {
    var reader: std.Io.Reader = .fixed("  0\r\nSECTION\r\n  2\nHEADER\n");
    var ascii = AsciiTokenizer.init(&reader);
    var tok = ascii.tokenizer();

    const first = (try tok.next()).?;
    try std.testing.expectEqual(@as(i16, 0), first.code);
    try std.testing.expectEqualStrings("SECTION", first.raw());
    try std.testing.expectEqual(@as(?u64, 1), first.loc.code_line);
    try std.testing.expectEqual(@as(?u64, 2), first.loc.value_line);

    const second = (try tok.next()).?;
    try std.testing.expectEqual(@as(i16, 2), second.code);
    try std.testing.expectEqualStrings("HEADER", second.raw());
    try std.testing.expectEqual(@as(?u64, 3), second.loc.code_line);
    try std.testing.expectEqual(@as(?u64, 4), second.loc.value_line);

    try std.testing.expectEqual(@as(?Token, null), try tok.next());
}

test "peek does not advance underlying token" {
    var reader: std.Io.Reader = .fixed("0\nEOF\n");
    var ascii = AsciiTokenizer.init(&reader);
    var tok = ascii.tokenizer();

    const peeked = (try tok.peek()).?;
    try std.testing.expectEqual(@as(i16, 0), peeked.code);
    try std.testing.expectEqualStrings("EOF", peeked.raw());

    const next_token = (try tok.next()).?;
    try std.testing.expectEqual(@as(i16, 0), next_token.code);
    try std.testing.expectEqualStrings("EOF", next_token.raw());

    try std.testing.expectEqual(@as(?Token, null), try tok.next());
}

test "invalid group code" {
    var reader: std.Io.Reader = .fixed("abc\nvalue\n");
    var ascii = AsciiTokenizer.init(&reader);
    var tok = ascii.tokenizer();

    try std.testing.expectError(error.InvalidGroupCode, tok.next());
}

test "missing group value" {
    var reader: std.Io.Reader = .fixed("0\n");
    var ascii = AsciiTokenizer.init(&reader);
    var tok = ascii.tokenizer();

    try std.testing.expectError(error.MissingGroupValue, tok.next());
}
