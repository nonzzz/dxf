const std = @import("std");
const parse = @import("parse");
const tokenizer = @import("tokenizer");
const common = @import("./common.zig");

pub const Text = @This();

loc: tokenizer.Tokenizer.Loc,
layer: ?[]const u8 = null,
value: ?[]const u8 = null,
start: common.Vec3 = .{},
alignment: ?common.Vec3 = null,
height: f64 = 0,
rotation: f64 = 0,
x_scale: f64 = 1,
oblique: f64 = 0,
style: ?[]const u8 = null,
text_generation_flags: i16 = 0,
horizontal_justification: i16 = 0,
vertical_justification: i16 = 0,
extrusion: common.Vec3 = .{ .z = 1 },

pub fn read(parser: *parse.Parser, start: parse.EntityStart) common.ReadError!Text {
    var text: Text = .{ .loc = start.loc };

    while (try parser.next()) |event| {
        switch (event) {
            .pair => |token| try text.apply(token),
            .entity_end => return text,
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}

fn apply(self: *Text, token: tokenizer.Tokenizer.Token) common.ReadError!void {
    switch (token.code) {
        1 => self.value = token.raw(),
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
        71 => self.text_generation_flags = try token.int(i16),
        72 => self.horizontal_justification = try token.int(i16),
        73 => self.vertical_justification = try token.int(i16),
        210 => self.extrusion.x = try token.float(f64),
        220 => self.extrusion.y = try token.float(f64),
        230 => self.extrusion.z = try token.float(f64),
        else => {},
    }
}

test "read TEXT entity" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nTEXT\n" ++
            "8\nNotes\n" ++
            "10\n1.0\n" ++
            "20\n2.0\n" ++
            "30\n3.0\n" ++
            "40\n4.0\n" ++
            "1\nHello\n" ++
            "50\n45.0\n" ++
            "41\n0.8\n" ++
            "51\n10.0\n" ++
            "7\nSTANDARD\n" ++
            "71\n2\n" ++
            "72\n1\n" ++
            "73\n3\n" ++
            "11\n5.0\n" ++
            "21\n6.0\n" ++
            "31\n7.0\n" ++
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

    const text = try Text.read(&parser, start);
    try std.testing.expectEqual(.text, start.kind);
    try std.testing.expectEqualStrings("Notes", text.layer.?);
    try std.testing.expectEqualStrings("Hello", text.value.?);
    try std.testing.expectEqualStrings("STANDARD", text.style.?);
    try std.testing.expectEqual(@as(f64, 1.0), text.start.x);
    try std.testing.expectEqual(@as(f64, 2.0), text.start.y);
    try std.testing.expectEqual(@as(f64, 3.0), text.start.z);
    try std.testing.expectEqual(@as(f64, 4.0), text.height);
    try std.testing.expectEqual(@as(f64, 45.0), text.rotation);
    try std.testing.expectEqual(@as(f64, 0.8), text.x_scale);
    try std.testing.expectEqual(@as(f64, 10.0), text.oblique);
    try std.testing.expectEqual(@as(i16, 2), text.text_generation_flags);
    try std.testing.expectEqual(@as(i16, 1), text.horizontal_justification);
    try std.testing.expectEqual(@as(i16, 3), text.vertical_justification);
    try std.testing.expectEqual(@as(f64, 5.0), text.alignment.?.x);
    try std.testing.expectEqual(@as(f64, 6.0), text.alignment.?.y);
    try std.testing.expectEqual(@as(f64, 7.0), text.alignment.?.z);
    try std.testing.expectEqual(@as(f64, 1.0), text.extrusion.z);
}

test "read TEXT ignores subclass and uses defaults" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nTEXT\n" ++
            "100\nAcDbEntity\n" ++
            "8\nNotes\n" ++
            "100\nAcDbText\n" ++
            "10\n1\n" ++
            "20\n2\n" ++
            "40\n3\n" ++
            "1\nHi\n" ++
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

    const text = try Text.read(&parser, start);
    try std.testing.expectEqual(.text, start.kind);
    try std.testing.expectEqualStrings("Notes", text.layer.?);
    try std.testing.expectEqualStrings("Hi", text.value.?);
    try std.testing.expectEqual(@as(f64, 1), text.start.x);
    try std.testing.expectEqual(@as(f64, 2), text.start.y);
    try std.testing.expectEqual(@as(f64, 3), text.height);
    try std.testing.expectEqual(@as(f64, 1), text.x_scale);
    try std.testing.expectEqual(@as(f64, 1), text.extrusion.z);
    try std.testing.expectEqual(@as(?common.Vec3, null), text.alignment);
}
