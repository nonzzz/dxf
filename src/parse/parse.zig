const std = @import("std");
const tokenizer_mod = @import("tokenizer");
const Tokenizer = tokenizer_mod.Tokenizer;
const event_mod = @import("./event.zig");
const kind = @import("./kind.zig");
const diagnostic_mod = @import("./diagnostic.zig");

const Parser = @This();

tokenizer: *Tokenizer,
state: State = .root,
section: kind.SectionKind = .unknown,
table: kind.TableKind = .unknown,
active_parent: Parent = .root,
options: diagnostic_mod.Options = .{},

pub const Event = event_mod.Event;
pub const Options = diagnostic_mod.Options;
pub const Diagnostics = diagnostic_mod.Diagnostics;
pub const Diagnostic = diagnostic_mod.Diagnostic;
pub const Severity = diagnostic_mod.Severity;
pub const DiagnosticCode = diagnostic_mod.DiagnosticCode;
pub const SectionKind = kind.SectionKind;
pub const TableKind = kind.TableKind;
pub const Marker = kind.Marker;

pub const State = enum {
    root,
    section,
    table,
    table_record,
    block,
    class,
    entity,
    object,
};

const Parent = enum {
    root,
    section,
    table,
    block,
};

pub const Error = Tokenizer.Error || Tokenizer.ExpectError || error{
    InvalidSection,
    InvalidTable,
    NestedSection,
    UnexpectedEndSection,
    UnexpectedEndTable,
    UnexpectedEndBlock,
    UnexpectedEof,
    UnexpectedTable,
    UnexpectedBlock,
    UnexpectedRootRecord,
};

pub fn init(tokenizer: *Tokenizer, options: Options) Parser {
    return .{ .tokenizer = tokenizer, .options = options };
}

pub fn next(self: *Parser) Error!?Event {
    if (try self.close_active_before_next_marker()) |event| return event;

    const token = try self.tokenizer.next() orelse return try self.end_of_stream();

    if (token.code != 0) {
        return .{ .pair = token };
    }

    const value = token.raw();
    const marker = Marker.from_raw(value) orelse return try self.start_context_record(token);

    return switch (marker) {
        .section => try self.parse_section_start(token),
        .endsec => try self.end_section(token.loc),
        .eof => try self.eof_marker(token.loc),
        .table => try self.parse_table_start(token),
        .endtab => try self.end_table(token.loc),
        .block => try self.start_block(token),
        .endblk => try self.end_block(token.loc),
    };
}

fn parse_section_start(self: *Parser, token: Tokenizer.Token) Error!Event {
    if (self.state != .root) {
        try self.issue(.nested_section, token.loc, error.NestedSection);
    }

    const name = try self.tokenizer.expect(2);
    if (name.raw().len == 0) return error.InvalidSection;
    self.state = .section;
    self.section = SectionKind.from_raw(name.raw());
    return .{ .section_start = .{
        .kind = self.section,
        .name = name.raw(),
        .loc = name.loc,
    } };
}

fn parse_table_start(self: *Parser, token: Tokenizer.Token) Error!Event {
    if (self.state != .section or self.section != .tables) {
        try self.issue(.unexpected_table, token.loc, error.UnexpectedTable);
        return .{ .pair = token };
    }

    const name = try self.tokenizer.expect(2);
    if (name.raw().len == 0) return error.InvalidTable;
    self.state = .table;
    self.table = TableKind.from_raw(name.raw());
    return .{ .table_start = .{
        .kind = self.table,
        .name = name.raw(),
        .loc = name.loc,
    } };
}

fn end_section(self: *Parser, loc: Tokenizer.Loc) Error!Event {
    if (self.state == .root) {
        try self.issue(.unexpected_endsec, loc, error.UnexpectedEndSection);
    }
    if (self.state == .table) {
        try self.issue(.unexpected_endtab, loc, error.UnexpectedEndTable);
    }
    if (self.state == .block) {
        try self.issue(.unexpected_endblk, loc, error.UnexpectedEndBlock);
    }

    self.state = .root;
    self.section = .unknown;
    self.table = .unknown;
    self.active_parent = .root;
    return .{ .section_end = .{ .loc = loc } };
}

fn eof_marker(self: *Parser, loc: Tokenizer.Loc) Error!?Event {
    switch (self.state) {
        .root => return null,
        .section => try self.issue(.eof_before_endsec, loc, error.UnexpectedEof),
        .table => try self.issue(.eof_before_endtab, loc, error.UnexpectedEof),
        .block => try self.issue(.eof_before_endblk, loc, error.UnexpectedEof),
        .table_record, .class, .entity, .object => unreachable,
    }

    self.state = .root;
    self.section = .unknown;
    self.table = .unknown;
    self.active_parent = .root;
    return null;
}

fn end_table(self: *Parser, loc: Tokenizer.Loc) Error!Event {
    if (self.state != .table) {
        try self.issue(.unexpected_endtab, loc, error.UnexpectedEndTable);
        return .{ .table_end = .{ .loc = loc } };
    }

    if (self.state == .table) {
        self.state = .section;
        self.table = .unknown;
        self.active_parent = .section;
    }
    return .{ .table_end = .{ .loc = loc } };
}

fn start_block(self: *Parser, token: Tokenizer.Token) Error!Event {
    if (self.state != .section or self.section != .blocks) {
        try self.issue(.unexpected_block, token.loc, error.UnexpectedBlock);
        return .{ .pair = token };
    }

    self.state = .block;
    self.active_parent = .section;
    return .{ .block_start = .{ .loc = token.loc } };
}

fn end_block(self: *Parser, loc: Tokenizer.Loc) Error!Event {
    if (self.state != .block) {
        try self.issue(.unexpected_endblk, loc, error.UnexpectedEndBlock);
        return .{ .block_end = .{ .loc = loc } };
    }

    self.state = .section;
    self.active_parent = .section;
    return .{ .block_end = .{ .loc = loc } };
}

fn start_context_record(self: *Parser, token: Tokenizer.Token) Error!Event {
    return switch (self.state) {
        .root => try self.unexpected_root_record(token),
        .section => switch (self.section) {
            .classes => self.start_class(token),
            .entities => self.start_entity(token, .section),
            .objects => self.start_object(token),
            else => .{ .pair = token },
        },
        .table => self.start_table_record(token),
        .block => self.start_entity(token, .block),
        else => .{ .pair = token },
    };
}

fn unexpected_root_record(self: *Parser, token: Tokenizer.Token) Error!Event {
    try self.issue(.unexpected_root_record, token.loc, error.UnexpectedRootRecord);
    return .{ .pair = token };
}

fn start_table_record(self: *Parser, token: Tokenizer.Token) Event {
    self.state = .table_record;
    self.active_parent = .table;
    return .{ .table_record_start = .{
        .table = self.table,
        .kind = token.raw(),
        .loc = token.loc,
    } };
}

fn start_class(self: *Parser, token: Tokenizer.Token) Event {
    self.state = .class;
    self.active_parent = .section;
    return .{ .class_start = .{
        .kind = token.raw(),
        .loc = token.loc,
    } };
}

fn start_entity(self: *Parser, token: Tokenizer.Token, parent: Parent) Event {
    self.state = .entity;
    self.active_parent = parent;
    return .{ .entity_start = .{
        .kind = kind.EntityKind.from_raw(token.raw()),
        .name = token.raw(),
        .loc = token.loc,
    } };
}

fn start_object(self: *Parser, token: Tokenizer.Token) Event {
    self.state = .object;
    self.active_parent = .section;
    return .{ .object_start = .{
        .kind = token.raw(),
        .loc = token.loc,
    } };
}

fn close_active_before_next_marker(self: *Parser) Error!?Event {
    switch (self.state) {
        .table_record, .class, .entity, .object => {},
        else => return null,
    }

    const next_token = try self.tokenizer.peek() orelse return self.close_active(.{});
    if (next_token.code != 0) return null;
    return self.close_active(next_token.loc);
}

fn close_active(self: *Parser, loc: Tokenizer.Loc) ?Event {
    const event: Event = switch (self.state) {
        .table_record => .{ .table_record_end = .{ .loc = loc } },
        .class => .{ .class_end = .{ .loc = loc } },
        .entity => .{ .entity_end = .{ .loc = loc } },
        .object => .{ .object_end = .{ .loc = loc } },
        else => return null,
    };

    self.state = switch (self.active_parent) {
        .root => .root,
        .section => .section,
        .table => .table,
        .block => .block,
    };
    self.active_parent = .root;
    return event;
}

fn end_of_stream(self: *Parser) Error!?Event {
    return switch (self.state) {
        .root => null,
        .section => {
            try self.issue(.eof_before_endsec, .{}, error.UnexpectedEof);
            return null;
        },
        .table => {
            try self.issue(.eof_before_endtab, .{}, error.UnexpectedEof);
            return null;
        },
        .block => {
            try self.issue(.eof_before_endblk, .{}, error.UnexpectedEof);
            return null;
        },
        .table_record, .class, .entity, .object => self.close_active(.{}),
    };
}

fn issue(self: *Parser, code: DiagnosticCode, loc: Tokenizer.Loc, err: Error) Error!void {
    if (self.options.diagnostics) |diagnostics| {
        diagnostics.emit(.{
            .severity = if (self.options.strict) .err else .warning,
            .code = code,
            .loc = loc,
        });
    }

    if (self.options.strict) return err;
}

const TestDiagnostics = struct {
    items: [8]Diagnostic = undefined,
    len: usize = 0,

    fn diagnostics(self: *@This()) Diagnostics {
        return .{
            .ptr = self,
            .vtable = &.{
                .emit = emit,
            },
        };
    }

    fn emit(ptr: *anyopaque, diagnostic: Diagnostic) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.items[self.len] = diagnostic;
        self.len += 1;
    }
};

fn expect_event_tag(maybe_event: ?Event, expected: std.meta.Tag(Event)) !void {
    const actual = maybe_event orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(expected, std.meta.activeTag(actual));
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
    var parser = Parser.init(&tok, .{});

    const section = (try parser.next()).?;
    switch (section) {
        .section_start => |section_start| {
            try std.testing.expectEqual(.header, section_start.kind);
            try std.testing.expectEqualStrings("HEADER", section_start.name);
        },
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

    try expect_event_tag(try parser.next(), .section_end);

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
    var parser = Parser.init(&tok, .{});

    switch ((try parser.next()).?) {
        .section_start => |section_start| {
            try std.testing.expectEqual(.tables, section_start.kind);
            try std.testing.expectEqualStrings("TABLES", section_start.name);
        },
        else => return error.TestUnexpectedResult,
    }
    switch ((try parser.next()).?) {
        .table_start => |table_start| {
            try std.testing.expectEqual(.layer, table_start.kind);
            try std.testing.expectEqualStrings("LAYER", table_start.name);
        },
        else => return error.TestUnexpectedResult,
    }
    try expect_event_tag(try parser.next(), .table_end);
    try expect_event_tag(try parser.next(), .section_end);

    switch ((try parser.next()).?) {
        .section_start => |section_start| {
            try std.testing.expectEqual(.blocks, section_start.kind);
            try std.testing.expectEqualStrings("BLOCKS", section_start.name);
        },
        else => return error.TestUnexpectedResult,
    }
    try expect_event_tag(try parser.next(), .block_start);
    switch ((try parser.next()).?) {
        .pair => |token| {
            try std.testing.expectEqual(@as(i16, 2), token.code);
            try std.testing.expectEqualStrings("A_BLOCK", token.raw());
        },
        else => return error.TestUnexpectedResult,
    }
    try expect_event_tag(try parser.next(), .block_end);
    try expect_event_tag(try parser.next(), .section_end);
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
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    switch ((try parser.next()).?) {
        .entity_start => |entity_start| {
            try std.testing.expectEqual(.line, entity_start.kind);
            try std.testing.expectEqualStrings("LINE", entity_start.name);
        },
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

test "entity ends before next marker" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nLINE\n" ++
            "8\n0\n" ++
            "0\nCIRCLE\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    switch ((try parser.next()).?) {
        .entity_start => |entity_start| {
            try std.testing.expectEqual(.line, entity_start.kind);
            try std.testing.expectEqualStrings("LINE", entity_start.name);
        },
        else => return error.TestUnexpectedResult,
    }
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .entity_end);
    switch ((try parser.next()).?) {
        .entity_start => |entity_start| {
            try std.testing.expectEqual(.circle, entity_start.kind);
            try std.testing.expectEqualStrings("CIRCLE", entity_start.name);
        },
        else => return error.TestUnexpectedResult,
    }
    try expect_event_tag(try parser.next(), .entity_end);
    try expect_event_tag(try parser.next(), .section_end);
}

test "parse class and object records for post R12 files" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nCLASSES\n" ++
            "0\nCLASS\n" ++
            "1\nACDBDICTIONARYWDFLT\n" ++
            "0\nENDSEC\n" ++
            "0\nSECTION\n" ++
            "2\nOBJECTS\n" ++
            "0\nDICTIONARY\n" ++
            "5\nC\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    switch ((try parser.next()).?) {
        .section_start => |section_start| try std.testing.expectEqual(.classes, section_start.kind),
        else => return error.TestUnexpectedResult,
    }
    switch ((try parser.next()).?) {
        .class_start => |class_start| try std.testing.expectEqualStrings("CLASS", class_start.kind),
        else => return error.TestUnexpectedResult,
    }
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .class_end);
    try expect_event_tag(try parser.next(), .section_end);

    switch ((try parser.next()).?) {
        .section_start => |section_start| try std.testing.expectEqual(.objects, section_start.kind),
        else => return error.TestUnexpectedResult,
    }
    switch ((try parser.next()).?) {
        .object_start => |object_start| try std.testing.expectEqualStrings("DICTIONARY", object_start.kind),
        else => return error.TestUnexpectedResult,
    }
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .object_end);
    try expect_event_tag(try parser.next(), .section_end);
}

test "parse table records" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nTABLES\n" ++
            "0\nTABLE\n" ++
            "2\nBLOCK_RECORD\n" ++
            "0\nBLOCK_RECORD\n" ++
            "2\n*MODEL_SPACE\n" ++
            "0\nENDTAB\n" ++
            "0\nENDSEC\n" ++
            "0\nEOF\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    switch ((try parser.next()).?) {
        .table_start => |table_start| try std.testing.expectEqual(.block_record, table_start.kind),
        else => return error.TestUnexpectedResult,
    }
    switch ((try parser.next()).?) {
        .table_record_start => |record| {
            try std.testing.expectEqual(.block_record, record.table);
            try std.testing.expectEqualStrings("BLOCK_RECORD", record.kind);
        },
        else => return error.TestUnexpectedResult,
    }
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .table_record_end);
    try expect_event_tag(try parser.next(), .table_end);
    try expect_event_tag(try parser.next(), .section_end);
}

test "section requires group code 2 name" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n9\n$ACADVER\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    try std.testing.expectError(error.UnexpectedCode, parser.next());
}

test "strict mode rejects unexpected section end" {
    var reader: std.Io.Reader = .fixed("0\nENDSEC\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    try std.testing.expectError(error.UnexpectedEndSection, parser.next());
}

test "lax mode reports unexpected section end and continues" {
    var reader: std.Io.Reader = .fixed("0\nENDSEC\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    try expect_event_tag(try parser.next(), .section_end);
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.warning, diagnostics.items[0].severity);
    try std.testing.expectEqual(.unexpected_endsec, diagnostics.items[0].code);
}

test "strict mode rejects eof before section end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nHEADER\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedEof, parser.next());
}

test "lax mode reports eof before section end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nHEADER\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    try std.testing.expectEqual(@as(?Event, null), try parser.next());
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.warning, diagnostics.items[0].severity);
    try std.testing.expectEqual(.eof_before_endsec, diagnostics.items[0].code);
}

test "strict mode rejects root records" {
    var reader: std.Io.Reader = .fixed("0\nLINE\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    try std.testing.expectError(error.UnexpectedRootRecord, parser.next());
}

test "lax mode reports root records as pairs" {
    var reader: std.Io.Reader = .fixed("0\nLINE\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    switch ((try parser.next()).?) {
        .pair => |token| {
            try std.testing.expectEqual(@as(i16, 0), token.code);
            try std.testing.expectEqualStrings("LINE", token.raw());
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.unexpected_root_record, diagnostics.items[0].code);
}

test "strict mode rejects table outside tables section" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nENTITIES\n0\nTABLE\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedTable, parser.next());
}

test "lax mode reports table outside tables section as pair" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nENTITIES\n0\nTABLE\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    switch ((try parser.next()).?) {
        .pair => |token| try std.testing.expectEqualStrings("TABLE", token.raw()),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.unexpected_table, diagnostics.items[0].code);
}

test "strict mode rejects block outside blocks section" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nENTITIES\n0\nBLOCK\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedBlock, parser.next());
}

test "lax mode reports block outside blocks section as pair" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nENTITIES\n0\nBLOCK\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    switch ((try parser.next()).?) {
        .pair => |token| try std.testing.expectEqualStrings("BLOCK", token.raw()),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.unexpected_block, diagnostics.items[0].code);
}

test "strict mode rejects nested sections" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nHEADER\n" ++
            "0\nSECTION\n" ++
            "2\nENTITIES\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    try std.testing.expectError(error.NestedSection, parser.next());
}

test "lax mode reports nested sections and starts the new section" {
    var reader: std.Io.Reader = .fixed(
        "0\nSECTION\n" ++
            "2\nHEADER\n" ++
            "0\nSECTION\n" ++
            "2\nENTITIES\n" ++
            "0\nENDSEC\n",
    );
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    switch ((try parser.next()).?) {
        .section_start => |section_start| try std.testing.expectEqual(.entities, section_start.kind),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.nested_section, diagnostics.items[0].code);
}

test "strict mode rejects eof before table end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedEof, parser.next());
}

test "strict mode rejects eof before block end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedEof, parser.next());
}

test "strict mode rejects eof marker before section end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nHEADER\n0\nEOF\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedEof, parser.next());
}

test "lax mode reports eof marker before section end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nHEADER\n0\nEOF\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    try std.testing.expectEqual(@as(?Event, null), try parser.next());
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.eof_before_endsec, diagnostics.items[0].code);
}

test "physical eof emits active entity end before strict section eof error" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n0\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    _ = try parser.next();
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .entity_end);
    try std.testing.expectError(error.UnexpectedEof, parser.next());
}

test "eof marker emits active entity end before strict section eof error" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n0\n0\nEOF\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    _ = try parser.next();
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .entity_end);
    try std.testing.expectError(error.UnexpectedEof, parser.next());
}

test "lax mode reports section eof after active entity end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n0\n0\nEOF\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    _ = try parser.next();
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .entity_end);
    try std.testing.expectEqual(@as(?Event, null), try parser.next());
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.eof_before_endsec, diagnostics.items[0].code);
}

test "strict mode rejects section end before table end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n0\nENDSEC\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedEndTable, parser.next());
}

test "lax mode reports section end before table end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n0\nENDSEC\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .section_end);
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.unexpected_endtab, diagnostics.items[0].code);
}

test "strict mode rejects section end before block end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n0\nENDSEC\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var parser = Parser.init(&tok, .{});

    _ = try parser.next();
    _ = try parser.next();
    try std.testing.expectError(error.UnexpectedEndBlock, parser.next());
}

test "lax mode reports section end before block end" {
    var reader: std.Io.Reader = .fixed("0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n0\nENDSEC\n");
    var ascii = tokenizer_mod.Ascii.init(&reader);
    var tok = ascii.tokenizer();
    var diagnostics = TestDiagnostics{};
    var parser = Parser.init(&tok, .{
        .strict = false,
        .diagnostics = diagnostics.diagnostics(),
    });

    _ = try parser.next();
    _ = try parser.next();
    try expect_event_tag(try parser.next(), .section_end);
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(.unexpected_endblk, diagnostics.items[0].code);
}
