const std = @import("std");
const tokenizer = @import("tokenizer");
const parse = @import("parse");
const common = @import("./common.zig");
const Attrib = @import("./attrib.zig");

pub const Insert = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
block_name: ?[]const u8 = null,
insert: common.Vec3 = .{},
scale: common.Vec3 = .{ .x = 1, .y = 1, .z = 1 },
rotation: f64 = 0,
attributes_follow: bool = false,
column_count: i16 = 1,
row_count: i16 = 1,
column_spacing: f64 = 0,
row_spacing: f64 = 0,
extrusion: common.Vec3 = .{ .z = 1 },

pub const Error = common.Error;

pub const AttribSink = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        emit: *const fn (*anyopaque, Attrib) Error!void,
    };

    pub fn emit(self: AttribSink, attrib: Attrib) Error!void {
        return self.vtable.emit(self.ptr, attrib);
    }
};

pub fn read(parser: *parse.Parser, start: parse.EntityStart, sink: ?AttribSink) Error!Insert {
    var insert: Insert = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try insert.apply(token),
            .entity_end => break,
            else => return error.UnexpectedEvent,
        }
    } else return error.UnexpectedEof;

    if (!insert.attributes_follow) return insert;

    while (try parser.next()) |event| {
        switch (event) {
            .entity_start => |entity| switch (entity.kind) {
                .attrib => {
                    const attrib = try Attrib.read(parser, entity);
                    if (sink) |attrib_sink| try attrib_sink.emit(attrib);
                },
                .seqend => {
                    try common.skip(parser);
                    return insert;
                },
                else => return error.UnexpectedEvent,
            },
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply(self: *Insert, token: tokenizer.Tokenizer.Token) Error!void {
    switch (token.code) {
        2 => self.block_name = token.raw(),
        8 => self.layer = token.raw(),
        10 => self.insert.x = try token.float(f64),
        20 => self.insert.y = try token.float(f64),
        30 => self.insert.z = try token.float(f64),
        41 => self.scale.x = try token.float(f64),
        42 => self.scale.y = try token.float(f64),
        43 => self.scale.z = try token.float(f64),
        50 => self.rotation = try token.float(f64),
        44 => self.column_spacing = try token.float(f64),
        45 => self.row_spacing = try token.float(f64),
        70 => self.column_count = try token.int(i16),
        71 => self.row_count = try token.int(i16),
        66 => self.attributes_follow = try token.boolean(),
        210 => self.extrusion.x = try token.float(f64),
        220 => self.extrusion.y = try token.float(f64),
        230 => self.extrusion.z = try token.float(f64),
        else => {},
    }
}

const TestAttribSink = struct {
    items: [4]Attrib = undefined,
    len: usize = 0,

    fn sink(self: *@This()) AttribSink {
        return .{
            .ptr = self,
            .vtable = &.{
                .emit = emit,
            },
        };
    }

    fn emit(ptr: *anyopaque, attrib: Attrib) Error!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.items[self.len] = attrib;
        self.len += 1;
    }
};

test "read INSERT entity without attributes" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nINSERT\n" ++
            "8\nBlocks\n" ++
            "2\nDOOR\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "30\n3\n" ++
            "41\n2\n" ++
            "42\n3\n" ++
            "43\n4\n" ++
            "50\n90\n" ++
            "70\n2\n" ++
            "71\n3\n" ++
            "44\n10\n" ++
            "45\n20\n" ++
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

    const insert_entity = try Insert.read(&parser, start, null);
    try std.testing.expectEqual(.insert, start.kind);
    try std.testing.expectEqualStrings("Blocks", insert_entity.layer.?);
    try std.testing.expectEqualStrings("DOOR", insert_entity.block_name.?);
    try std.testing.expectEqual(@as(f64, 1), insert_entity.insert.x);
    try std.testing.expectEqual(@as(f64, 2), insert_entity.insert.y);
    try std.testing.expectEqual(@as(f64, 3), insert_entity.insert.z);
    try std.testing.expectEqual(@as(f64, 2), insert_entity.scale.x);
    try std.testing.expectEqual(@as(f64, 3), insert_entity.scale.y);
    try std.testing.expectEqual(@as(f64, 4), insert_entity.scale.z);
    try std.testing.expectEqual(@as(f64, 90), insert_entity.rotation);
    try std.testing.expectEqual(@as(i16, 2), insert_entity.column_count);
    try std.testing.expectEqual(@as(i16, 3), insert_entity.row_count);
    try std.testing.expectEqual(@as(f64, 10), insert_entity.column_spacing);
    try std.testing.expectEqual(@as(f64, 20), insert_entity.row_spacing);
}

test "read INSERT attributes through sink until SEQEND" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nINSERT\n" ++
            "2\nROOM_TAG\n" ++
            "66\n1\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "0\nATTRIB\n" ++
            "2\nROOM\n" ++
            "1\n101\n" ++
            "10\n3\n" ++
            "20\n4\n" ++
            "0\nATTRIB\n" ++
            "2\nNAME\n" ++
            "1\nOffice\n" ++
            "0\nSEQEND\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = parse.Parser.init(&tok, .{});
    var attrib_sink = TestAttribSink{};

    _ = try parser.next();
    const start = switch ((try parser.next()).?) {
        .entity_start => |entity| entity,
        else => return error.TestUnexpectedResult,
    };

    const insert_entity = try Insert.read(&parser, start, attrib_sink.sink());
    try std.testing.expectEqual(.insert, start.kind);
    try std.testing.expectEqualStrings("ROOM_TAG", insert_entity.block_name.?);
    try std.testing.expectEqual(true, insert_entity.attributes_follow);
    try std.testing.expectEqual(@as(usize, 2), attrib_sink.len);
    try std.testing.expectEqualStrings("ROOM", attrib_sink.items[0].tag.?);
    try std.testing.expectEqualStrings("101", attrib_sink.items[0].value.?);
    try std.testing.expectEqual(@as(f64, 3), attrib_sink.items[0].start.x);
    try std.testing.expectEqual(@as(f64, 4), attrib_sink.items[0].start.y);
    try std.testing.expectEqualStrings("NAME", attrib_sink.items[1].tag.?);
    try std.testing.expectEqualStrings("Office", attrib_sink.items[1].value.?);
}
