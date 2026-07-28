const std = @import("std");
const parse = @import("parse");
const tokenizer = @import("tokenizer");
const common = @import("./common.zig");

pub const Line = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
start: common.Vec3 = .{},
end: common.Vec3 = .{},

pub const Error = common.Error;

pub fn read(parser: *parse.Parser, start: parse.EntityStart) Error!Line {
    var line: Line = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try line.apply(token),
            .entity_end => return line,
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply(self: *Line, token: tokenizer.Tokenizer.Token) Error!void {
    switch (token.code) {
        8 => self.layer = token.raw(),
        10 => self.start.x = try token.float(f64),
        20 => self.start.y = try token.float(f64),
        30 => self.start.z = try token.float(f64),
        11 => self.end.x = try token.float(f64),
        21 => self.end.y = try token.float(f64),
        31 => self.end.z = try token.float(f64),
        else => {},
    }
}

test "read LINE entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nLINE\n" ++
            "8\n0\n" ++
            "10\n1.0\n" ++
            "20\n2.0\n" ++
            "30\n3.0\n" ++
            "11\n4.0\n" ++
            "21\n5.0\n" ++
            "31\n6.0\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = parse.Parser.init(&tok, .{});

    _ = try parser.next();
    const start = switch ((try parser.next()).?) {
        .entity_start => |entity| entity,
        else => return error.TestUnexpectedResult,
    };

    const line = try Line.read(&parser, start);
    try std.testing.expectEqual(.line, start.kind);
    try std.testing.expectEqualStrings("0", line.layer.?);
    try std.testing.expectEqual(@as(f64, 1.0), line.start.x);
    try std.testing.expectEqual(@as(f64, 2.0), line.start.y);
    try std.testing.expectEqual(@as(f64, 3.0), line.start.z);
    try std.testing.expectEqual(@as(f64, 4.0), line.end.x);
    try std.testing.expectEqual(@as(f64, 5.0), line.end.y);
    try std.testing.expectEqual(@as(f64, 6.0), line.end.z);
}

test "read LINE ignores R13 subclass and handle fields" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nLINE\n" ++
            "5\n2F\n" ++
            "100\nAcDbEntity\n" ++
            "8\nLayerA\n" ++
            "100\nAcDbLine\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "11\n3\n" ++
            "21\n4\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = parse.Parser.init(&tok, .{});

    _ = try parser.next();
    const start = switch ((try parser.next()).?) {
        .entity_start => |entity| entity,
        else => return error.TestUnexpectedResult,
    };

    const line = try Line.read(&parser, start);
    try std.testing.expectEqual(.line, start.kind);
    try std.testing.expectEqualStrings("LayerA", line.layer.?);
    try std.testing.expectEqual(@as(f64, 1), line.start.x);
    try std.testing.expectEqual(@as(f64, 2), line.start.y);
    try std.testing.expectEqual(@as(f64, 3), line.end.x);
    try std.testing.expectEqual(@as(f64, 4), line.end.y);
}
