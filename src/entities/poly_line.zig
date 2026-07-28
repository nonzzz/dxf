const std = @import("std");
const parse = @import("parse");
const tokenizer = @import("tokenizer");
const common = @import("./common.zig");

pub const PolyLine = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
flags: i16 = 0,
closed: bool = false,

pub const Vertex = struct {
    loc: tokenizer.Tokenizer.Loc,
    layer: ?[]const u8 = null,
    point: common.Vec3 = .{},
    flags: i16 = 0,
};

pub const VertexSink = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        emit: *const fn (*anyopaque, Vertex) Error!void,
    };

    pub fn emit(self: VertexSink, vertex: Vertex) Error!void {
        return self.vtable.emit(self.ptr, vertex);
    }
};

pub const Error = common.Error;

pub fn read(parser: *parse.Parser, start: parse.EntityStart, sink: ?VertexSink) Error!PolyLine {
    var polyline: PolyLine = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try polyline.apply(token),
            .entity_end => break,
            else => return error.UnexpectedEvent,
        }
    } else return error.UnexpectedEof;

    while (try parser.next()) |event| {
        switch (event) {
            .entity_start => |entity| switch (entity.kind) {
                .vertex => {
                    const vertex = try read_vertex(parser, entity);
                    if (sink) |vertex_sink| try vertex_sink.emit(vertex);
                },
                .seqend => {
                    try common.skip(parser);
                    return polyline;
                },
                else => return error.UnexpectedEvent,
            },
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply(self: *PolyLine, token: tokenizer.Tokenizer.Token) Error!void {
    switch (token.code) {
        8 => self.layer = token.raw(),
        70 => {
            self.flags = try token.int(i16);
            self.closed = (self.flags & 1) != 0;
        },
        else => {},
    }
}

fn read_vertex(parser: *parse.Parser, start: parse.EntityStart) Error!Vertex {
    var vertex: Vertex = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try apply_vertex(&vertex, token),
            .entity_end => return vertex,
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply_vertex(vertex: *Vertex, token: tokenizer.Tokenizer.Token) Error!void {
    switch (token.code) {
        8 => vertex.layer = token.raw(),
        10 => vertex.point.x = try token.float(f64),
        20 => vertex.point.y = try token.float(f64),
        30 => vertex.point.z = try token.float(f64),
        70 => vertex.flags = try token.int(i16),
        else => {},
    }
}

const TestVertexSink = struct {
    items: [8]Vertex = undefined,
    len: usize = 0,

    fn sink(self: *@This()) VertexSink {
        return .{
            .ptr = self,
            .vtable = &.{
                .emit = emit,
            },
        };
    }

    fn emit(ptr: *anyopaque, vertex: Vertex) Error!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.items[self.len] = vertex;
        self.len += 1;
    }
};

test "read POLYLINE with VERTEX records until SEQEND" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nPOLYLINE\n" ++
            "8\nLayerA\n" ++
            "70\n1\n" ++
            "0\nVERTEX\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "30\n3\n" ++
            "0\nVERTEX\n" ++
            "10\n4\n" ++
            "20\n5\n" ++
            "30\n6\n" ++
            "0\nSEQEND\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = parse.Parser.init(&tok, .{});
    var vertex_sink = TestVertexSink{};

    _ = try parser.next();
    const start = switch ((try parser.next()).?) {
        .entity_start => |entity| entity,
        else => return error.TestUnexpectedResult,
    };

    const polyline = try PolyLine.read(&parser, start, vertex_sink.sink());
    try std.testing.expectEqual(.polyline, start.kind);
    try std.testing.expectEqualStrings("LayerA", polyline.layer.?);
    try std.testing.expectEqual(true, polyline.closed);
    try std.testing.expectEqual(@as(usize, 2), vertex_sink.len);
    try std.testing.expectEqual(@as(f64, 1), vertex_sink.items[0].point.x);
    try std.testing.expectEqual(@as(f64, 2), vertex_sink.items[0].point.y);
    try std.testing.expectEqual(@as(f64, 3), vertex_sink.items[0].point.z);
    try std.testing.expectEqual(@as(f64, 4), vertex_sink.items[1].point.x);
    try std.testing.expectEqual(@as(f64, 5), vertex_sink.items[1].point.y);
    try std.testing.expectEqual(@as(f64, 6), vertex_sink.items[1].point.z);
}
