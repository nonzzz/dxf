const std = @import("std");
const tokenizer_mod = @import("tokenizer");
const Tokenizer = tokenizer_mod.Tokenizer;

const Parser = @This();

tokenizer: *Tokenizer,

pub const Event = union(enum) {
    section_start: []const u8,
    section_end,

    table_start: []const u8,
    table_end,

    block_start,
    block_end,

    entity_start: []const u8,

    pair: Tokenizer.Token,
};

pub const Error = Tokenizer.Error || Tokenizer.ExpectError || error{
    InvalidSection,
    InvalidTable,
};

pub const Marker = enum {
    section,
    endsec,
    eof,
    table,
    endtab,
    block,
    endblk,

    pub fn from_raw(raw: []const u8) ?Marker {
        inline for (std.meta.fields(Marker)) |field| {
            const marker: Marker = @enumFromInt(field.value);
            if (std.mem.eql(u8, raw, marker.as_str())) return marker;
        }
        return null;
    }

    pub fn as_str(self: Marker) []const u8 {
        return switch (self) {
            .section => "SECTION",
            .endsec => "ENDSEC",
            .eof => "EOF",
            .table => "TABLE",
            .endtab => "ENDTAB",
            .block => "BLOCK",
            .endblk => "ENDBLK",
        };
    }
};

pub fn init(tokenizer: *Tokenizer) Parser {
    return .{ .tokenizer = tokenizer };
}

pub fn next(self: *Parser) Error!?Event {
    const token = try self.tokenizer.next() orelse return null;

    if (token.code != 0) {
        return .{ .pair = token };
    }

    const value = token.raw();
    const marker = Marker.from_raw(value) orelse return .{ .entity_start = value };

    return switch (marker) {
        .section => try self.parse_section_start(),
        .endsec => .section_end,
        .eof => null,
        .table => try self.parse_table_start(),
        .endtab => .table_end,
        .block => .block_start,
        .endblk => .block_end,
    };
}

fn parse_section_start(self: *Parser) Error!Event {
    const name = try self.tokenizer.expect(2);
    if (name.raw().len == 0) return error.InvalidSection;
    return .{ .section_start = name.raw() };
}

fn parse_table_start(self: *Parser) Error!Event {
    const name = try self.tokenizer.expect(2);
    if (name.raw().len == 0) return error.InvalidTable;
    return .{ .table_start = name.raw() };
}

test "parse section events" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nHEADER\n" ++
            "9\n$ACADVER\n" ++
            "1\nAC1032\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok);

    const section = (try parser.next()).?;
    switch (section) {
        .section_start => |name| try std.testing.expectEqualStrings("HEADER", name),
        else => return error.TestUnexpectedResult,
    }

    const pair_1 = (try parser.next()).?;
    switch (pair_1) {
        .pair => |token| {
            try std.testing.expectEqual(@as(i16, 9), token.code);
            try std.testing.expectEqualStrings("$ACADVER", token.raw());
        },
        else => return error.TestUnexpectedResult,
    }

    const pair_2 = (try parser.next()).?;
    switch (pair_2) {
        .pair => |token| {
            try std.testing.expectEqual(@as(i16, 1), token.code);
            try std.testing.expectEqualStrings("AC1032", token.raw());
        },
        else => return error.TestUnexpectedResult,
    }

    const section_end = (try parser.next()).?;
    try std.testing.expect(section_end == .section_end);

    try std.testing.expectEqual(@as(?Event, null), try parser.next());
}

test "parse table and block events" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nTABLES\n" ++
            "0\nTABLE\n" ++
            "2\nLAYER\n" ++
            "0\nENDTAB\n" ++
            "0\nENDSEC\n" ++
            "0\nSECTION\n" ++
            "2\nBLOCKS\n" ++
            "0\nBLOCK\n" ++
            "2\nA_BLOCK\n" ++
            "0\nENDBLK\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok);

    switch ((try parser.next()).?) {
        .section_start => |name| try std.testing.expectEqualStrings("TABLES", name),
        else => return error.TestUnexpectedResult,
    }
    switch ((try parser.next()).?) {
        .table_start => |name| try std.testing.expectEqualStrings("LAYER", name),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect((try parser.next()).? == .table_end);
    try std.testing.expect((try parser.next()).? == .section_end);

    switch ((try parser.next()).?) {
        .section_start => |name| try std.testing.expectEqualStrings("BLOCKS", name),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect((try parser.next()).? == .block_start);
    switch ((try parser.next()).?) {
        .pair => |token| {
            try std.testing.expectEqual(@as(i16, 2), token.code);
            try std.testing.expectEqualStrings("A_BLOCK", token.raw());
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect((try parser.next()).? == .block_end);
    try std.testing.expect((try parser.next()).? == .section_end);
    try std.testing.expectEqual(@as(?Event, null), try parser.next());
}

test "parse entity start" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nLINE\n" ++
            "8\n0\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok);

    _ = try parser.next();
    switch ((try parser.next()).?) {
        .entity_start => |name| try std.testing.expectEqualStrings("LINE", name),
        else => return error.TestUnexpectedResult,
    }
    switch ((try parser.next()).?) {
        .pair => |token| {
            try std.testing.expectEqual(@as(i16, 8), token.code);
            try std.testing.expectEqualStrings("0", token.raw());
        },
        else => return error.TestUnexpectedResult,
    }
}

test "section requires group code 2 name" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n9\n$ACADVER\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok);

    try std.testing.expectError(error.UnexpectedCode, parser.next());
}
