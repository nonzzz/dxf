const std = @import("std");
const parse = @import("parse");
const tokenizer = @import("tokenizer");
const common = @import("./common.zig");

pub const Arc = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
center: common.Vec3 = .{},
radius: f64 = 0,
thickness: f64 = 0,
start_angle: f64 = 0,
end_angle: f64 = 0,
extrusion: common.Vec3 = .{ .z = 1 },

pub fn read(parser: *parse.Parser, start: parse.EntityStart) common.ReadError!Arc {
    var arc: Arc = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try arc.apply(token),
            .entity_end => return arc,
            else => return error.UnexpectedEvent,
        }
    }
    return error.UnexpectedEof;
}

fn apply(self: *Arc, token: tokenizer.Tokenizer.Token) common.ReadError!void {
    switch (token.code) {
        8 => self.layer = token.raw(),
        39 => self.thickness = try token.float(f64),
        10 => self.center.x = try token.float(f64),
        20 => self.center.y = try token.float(f64),
        30 => self.center.z = try token.float(f64),
        40 => self.radius = try token.float(f64),
        50 => self.start_angle = try token.float(f64),
        51 => self.end_angle = try token.float(f64),
        210 => self.extrusion.x = try token.float(f64),
        220 => self.extrusion.y = try token.float(f64),
        230 => self.extrusion.z = try token.float(f64),
        else => {},
    }
}

test "read ARC entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nARC\n" ++
            "8\n0\n" ++
            "39\n2.0\n" ++
            "10\n1.0\n" ++
            "20\n2.0\n" ++
            "30\n3.0\n" ++
            "40\n4.0\n" ++
            "50\n45.0\n" ++
            "51\n90.0\n" ++
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

    const arc = try Arc.read(&parser, start);
    try std.testing.expectEqual(.arc, start.kind);
    try std.testing.expectEqualStrings("0", arc.layer.?);
    try std.testing.expectEqual(@as(f64, 2.0), arc.thickness);
    try std.testing.expectEqual(@as(f64, 1.0), arc.center.x);
    try std.testing.expectEqual(@as(f64, 2.0), arc.center.y);
    try std.testing.expectEqual(@as(f64, 3.0), arc.center.z);
    try std.testing.expectEqual(@as(f64, 4.0), arc.radius);
    try std.testing.expectEqual(@as(f64, 45.0), arc.start_angle);
    try std.testing.expectEqual(@as(f64, 90.0), arc.end_angle);
    try std.testing.expectEqual(@as(f64, 1.0), arc.extrusion.z);
}

test "read ARC ignores R13 subclass fields and uses default extrusion" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nARC\n" ++
            "100\nAcDbCircle\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "40\n3\n" ++
            "100\nAcDbArc\n" ++
            "50\n0\n" ++
            "51\n180\n" ++
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

    const arc = try Arc.read(&parser, start);
    try std.testing.expectEqual(.arc, start.kind);
    try std.testing.expectEqual(@as(f64, 1), arc.center.x);
    try std.testing.expectEqual(@as(f64, 2), arc.center.y);
    try std.testing.expectEqual(@as(f64, 3), arc.radius);
    try std.testing.expectEqual(@as(f64, 0), arc.start_angle);
    try std.testing.expectEqual(@as(f64, 180), arc.end_angle);
    try std.testing.expectEqual(@as(f64, 0), arc.extrusion.x);
    try std.testing.expectEqual(@as(f64, 0), arc.extrusion.y);
    try std.testing.expectEqual(@as(f64, 1), arc.extrusion.z);
}
