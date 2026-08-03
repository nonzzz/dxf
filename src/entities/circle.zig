const std = @import("std");
const parse = @import("parse");
const tokenizer = @import("tokenizer");
const common = @import("./common.zig");

pub const Circle = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
center: common.Vec3 = .{},
radius: f64 = 0,

pub fn read(parser: *parse.Parser, start: parse.EntityStart) common.ReadError!Circle {
    var circle: Circle = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try circle.apply(token),
            .entity_end => return circle,
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply(self: *Circle, token: tokenizer.Tokenizer.Token) common.ReadError!void {
    switch (token.code) {
        8 => self.layer = token.raw(),
        10 => self.center.x = try token.float(f64),
        20 => self.center.y = try token.float(f64),
        30 => self.center.z = try token.float(f64),
        40 => self.radius = try token.float(f64),
        else => {},
    }
}

test "read CIRCLE entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nCIRCLE\n" ++
            "8\n0\n" ++
            "10\n1.0\n" ++
            "20\n2.0\n" ++
            "30\n3.0\n" ++
            "40\n4.0\n" ++
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

    const circle = try Circle.read(&parser, start);
    try std.testing.expectEqual(.circle, start.kind);
    try std.testing.expectEqualStrings("0", circle.layer.?);
    try std.testing.expectEqual(@as(f64, 1.0), circle.center.x);
    try std.testing.expectEqual(@as(f64, 2.0), circle.center.y);
    try std.testing.expectEqual(@as(f64, 3.0), circle.center.z);
    try std.testing.expectEqual(@as(f64, 4.0), circle.radius);
}
