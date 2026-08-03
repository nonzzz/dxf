const std = @import("std");
const tokenizer = @import("tokenizer");
const parse = @import("parse");

pub const common = @import("./common.zig");
pub const Line = @import("./line.zig");
pub const Circle = @import("./circle.zig");
pub const Arc = @import("./arc.zig");
pub const PolyLine = @import("./poly_line.zig");
pub const Text = @import("./text.zig");
pub const Point = @import("./point.zig");
pub const Insert = @import("./insert.zig");
pub const Attrib = @import("./attrib.zig");
pub const AttDef = @import("./att_def.zig");

pub const Vec3 = common.Vec3;
pub const ReadError = common.ReadError;
pub const Error = ReadError;
pub const skip = common.skip;

pub const Entity = union(enum) {
    line: Line,
    circle: Circle,
    arc: Arc,
    polyline: PolyLine,
    text: Text,
    point: Point,
    insert: Insert,
    attrib: Attrib,
    attdef: AttDef,
    unknown: parse.EntityStart,
};

pub const ReadOptions = struct {
    polyline_vertex_sink: ?PolyLine.VertexSink = null,
    insert_attrib_sink: ?Insert.AttribSink = null,
};

pub fn read(parser: *parse.Parser, start: parse.EntityStart, options: ReadOptions) ReadError!Entity {
    return switch (start.kind) {
        .line => .{ .line = try Line.read(parser, start) },
        .circle => .{ .circle = try Circle.read(parser, start) },
        .arc => .{ .arc = try Arc.read(parser, start) },
        .polyline => .{ .polyline = try PolyLine.read(parser, start, options.polyline_vertex_sink) },
        .text => .{ .text = try Text.read(parser, start) },
        .point => .{ .point = try Point.read(parser, start) },
        .insert => .{ .insert = try Insert.read(parser, start, options.insert_attrib_sink) },
        .attrib => .{ .attrib = try Attrib.read(parser, start) },
        .attdef => .{ .attdef = try AttDef.read(parser, start) },
        else => {
            try skip(parser);
            return .{ .unknown = start };
        },
    };
}

test {
    _ = Line;
    _ = Circle;
    _ = Arc;
    _ = PolyLine;
    _ = Text;
    _ = Point;
    _ = Insert;
    _ = Attrib;
    _ = AttDef;
}

test "dispatch reads supported entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nLINE\n" ++
            "8\n0\n" ++
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

    const entity = try read(&parser, start, .{});
    switch (entity) {
        .line => |line| {
            try std.testing.expectEqualStrings("0", line.layer.?);
            try std.testing.expectEqual(@as(f64, 1), line.start.x);
            try std.testing.expectEqual(@as(f64, 2), line.start.y);
            try std.testing.expectEqual(@as(f64, 3), line.end.x);
            try std.testing.expectEqual(@as(f64, 4), line.end.y);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "dispatch skips unsupported entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nSOLID\n" ++
            "8\n0\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "0\nLINE\n" ++
            "10\n3\n" ++
            "20\n4\n" ++
            "11\n5\n" ++
            "21\n6\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = parse.Parser.init(&tok, .{});

    _ = try parser.next();
    const solid_start = switch ((try parser.next()).?) {
        .entity_start => |entity| entity,
        else => return error.TestUnexpectedResult,
    };

    const unknown = try read(&parser, solid_start, .{});
    switch (unknown) {
        .unknown => |start| try std.testing.expectEqual(.solid, start.kind),
        else => return error.TestUnexpectedResult,
    }

    const line_start = switch ((try parser.next()).?) {
        .entity_start => |entity| entity,
        else => return error.TestUnexpectedResult,
    };
    const line_entity = try read(&parser, line_start, .{});
    switch (line_entity) {
        .line => |line| try std.testing.expectEqual(@as(f64, 3), line.start.x),
        else => return error.TestUnexpectedResult,
    }
}
