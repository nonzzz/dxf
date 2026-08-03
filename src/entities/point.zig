const std = @import("std");
const parse = @import("parse");
const tokenizer = @import("tokenizer");
const common = @import("./common.zig");

pub const Point = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
location: common.Vec3 = .{},
thickness: f64 = 0,
angle: f64 = 0,
extrusion: common.Vec3 = .{ .z = 1 },

pub fn read(parser: *parse.Parser, start: parse.EntityStart) common.ReadError!Point {
    var point: Point = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try point.apply(token),
            .entity_end => return point,
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply(self: *Point, token: tokenizer.Tokenizer.Token) common.ReadError!void {
    switch (token.code) {
        8 => self.layer = token.raw(),
        10 => self.location.x = try token.float(f64),
        20 => self.location.y = try token.float(f64),
        30 => self.location.z = try token.float(f64),
        39 => self.thickness = try token.float(f64),
        50 => self.angle = try token.float(f64),
        210 => self.extrusion.x = try token.float(f64),
        220 => self.extrusion.y = try token.float(f64),
        230 => self.extrusion.z = try token.float(f64),
        else => {},
    }
}

test "read POINT entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nPOINT\n" ++
            "8\nPoints\n" ++
            "10\n1.0\n" ++
            "20\n2.0\n" ++
            "30\n3.0\n" ++
            "39\n4.0\n" ++
            "50\n45.0\n" ++
            "210\n0.0\n" ++
            "220\n0.0\n" ++
            "230\n1.0\n" ++
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

    const point = try Point.read(&parser, start);
    try std.testing.expectEqual(.point, start.kind);
    try std.testing.expectEqualStrings("Points", point.layer.?);
    try std.testing.expectEqual(@as(f64, 1.0), point.location.x);
    try std.testing.expectEqual(@as(f64, 2.0), point.location.y);
    try std.testing.expectEqual(@as(f64, 3.0), point.location.z);
    try std.testing.expectEqual(@as(f64, 4.0), point.thickness);
    try std.testing.expectEqual(@as(f64, 45.0), point.angle);
    try std.testing.expectEqual(@as(f64, 1.0), point.extrusion.z);
}

test "read POINT ignores subclass and uses default extrusion" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nPOINT\n" ++
            "100\nAcDbEntity\n" ++
            "8\nPoints\n" ++
            "100\nAcDbPoint\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "30\n3\n" ++
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

    const point = try Point.read(&parser, start);
    try std.testing.expectEqual(.point, start.kind);
    try std.testing.expectEqualStrings("Points", point.layer.?);
    try std.testing.expectEqual(@as(f64, 1), point.location.x);
    try std.testing.expectEqual(@as(f64, 2), point.location.y);
    try std.testing.expectEqual(@as(f64, 3), point.location.z);
    try std.testing.expectEqual(@as(f64, 0), point.thickness);
    try std.testing.expectEqual(@as(f64, 0), point.angle);
    try std.testing.expectEqual(@as(f64, 0), point.extrusion.x);
    try std.testing.expectEqual(@as(f64, 0), point.extrusion.y);
    try std.testing.expectEqual(@as(f64, 1), point.extrusion.z);
}
