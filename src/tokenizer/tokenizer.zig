const std = @import("std");

pub const Loc = struct {
    code_line: ?u64 = null,
    value_line: ?u64 = null,
    code_offset: ?u64 = null,
    value_offset: ?u64 = null,
};

pub const Token = struct {
    code: i16,
    value: RawValue,
    loc: Loc = .{},
    /// `raw()` is borrowed from the tokenizer implementation.
    /// It remains valid until the next tokenizer operation that advances input.
    pub fn raw(self: Token) []const u8 {
        return self.value.raw;
    }
};

pub const RawValue = union(enum) {
    raw: []const u8,
};

const Tokenizer = @This();

ptr: *anyopaque,
vtable: *const VTable,
peeked: ?Token = null,

pub const VTable = struct {
    next: *const fn (*anyopaque) Error!?Token,
};

pub fn next(self: *Tokenizer) Error!?Token {
    if (self.peeked) |tok| {
        self.peeked = null;
        return tok;
    }
    return self.vtable.next(self.ptr);
}

pub fn peek(self: *Tokenizer) Error!?Token {
    if (self.peeked == null) {
        self.peeked = try self.next();
    }
    return self.peeked;
}

pub fn expect(self: *Tokenizer, code: i16) ExpectError!Token {
    const tok = try self.next() orelse return error.UnexpectedEof;

    if (tok.code != code) {
        return error.UnexpectedCode;
    }

    return tok;
}

pub const Error = error{
    ReadFailed,
    InvalidGroupCode,
    MissingGroupValue,
    LineTooLong,
    UnsupportedEncoding,
};

pub const ExpectError = Error || error{
    UnexpectedEof,
    UnexpectedCode,
};
