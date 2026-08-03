const std = @import("std");
const parse = @import("parse");
const tokenizer = @import("tokenizer");
const common = @import("./common.zig");

pub const Attrib = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
tag: ?[]const u8 = null,
value: ?[]const u8 = null,
start: common.Vec3 = .{},
alignment: ?common.Vec3 = null,
height: f64 = 0,
rotation: f64 = 0,
x_scale: f64 = 1,
oblique: f64 = 0,
style: ?[]const u8 = null,
flags: i16 = 0,
text_generation_flags: i16 = 0,
horizontal_justification: i16 = 0,
field_length: i16 = 0,
vertical_justification: i16 = 0,
extrusion: common.Vec3 = .{ .z = 1 },

pub const Error = common.Error;

pub fn read(parser: *parse.Parser, start: parse.EntityStart) Error!Attrib {
    var attrib: Attrib = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try attrib.apply(token),
            .entity_end => return attrib,
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply(self: *Attrib, token: tokenizer.Tokenizer.Token) Error!void {
    switch (token.code) {
        1 => self.value = token.raw(),
        2 => self.tag = token.raw(),
        7 => self.style = token.raw(),
        8 => self.layer = token.raw(),
        10 => self.start.x = try token.float(f64),
        20 => self.start.y = try token.float(f64),
        30 => self.start.z = try token.float(f64),
        11 => {
            if (self.alignment == null) self.alignment = .{};
            self.alignment.?.x = try token.float(f64);
        },
        21 => {
            if (self.alignment == null) self.alignment = .{};
            self.alignment.?.y = try token.float(f64);
        },
        31 => {
            if (self.alignment == null) self.alignment = .{};
            self.alignment.?.z = try token.float(f64);
        },
        40 => self.height = try token.float(f64),
        41 => self.x_scale = try token.float(f64),
        50 => self.rotation = try token.float(f64),
        51 => self.oblique = try token.float(f64),
        70 => self.flags = try token.int(i16),
        71 => self.text_generation_flags = try token.int(i16),
        72 => self.horizontal_justification = try token.int(i16),
        73 => self.field_length = try token.int(i16),
        74 => self.vertical_justification = try token.int(i16),
        210 => self.extrusion.x = try token.float(f64),
        220 => self.extrusion.y = try token.float(f64),
        230 => self.extrusion.z = try token.float(f64),
        else => {},
    }
}

test "read ATTRIB entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nATTRIB\n" ++
            "8\nAnno\n" ++
            "2\nID\n" ++
            "1\nA-101\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "30\n3\n" ++
            "40\n4\n" ++
            "70\n1\n" ++
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

    const attrib = try Attrib.read(&parser, start);
    try std.testing.expectEqual(.attrib, start.kind);
    try std.testing.expectEqualStrings("Anno", attrib.layer.?);
    try std.testing.expectEqualStrings("ID", attrib.tag.?);
    try std.testing.expectEqualStrings("A-101", attrib.value.?);
    try std.testing.expectEqual(@as(f64, 1), attrib.start.x);
    try std.testing.expectEqual(@as(f64, 2), attrib.start.y);
    try std.testing.expectEqual(@as(f64, 3), attrib.start.z);
    try std.testing.expectEqual(@as(f64, 4), attrib.height);
    try std.testing.expectEqual(@as(i16, 1), attrib.flags);
}
