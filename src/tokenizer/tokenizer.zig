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

    pub fn int(self: Token, comptime T: type) ValueError!T {
        return std.fmt.parseInt(T, trimmed_raw(self), 10) catch return error.InvalidValue;
    }

    pub fn float(self: Token, comptime T: type) ValueError!T {
        return std.fmt.parseFloat(T, trimmed_raw(self)) catch return error.InvalidValue;
    }

    pub fn boolean(self: Token) ValueError!bool {
        const value = try self.int(i16);
        return switch (value) {
            0 => false,
            1 => true,
            else => error.InvalidValue,
        };
    }

    fn trimmed_raw(self: Token) []const u8 {
        return std.mem.trim(u8, self.raw(), " \t\r");
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

pub const ValueError = error{
    InvalidValue,
};

test "token value conversions" {
    const int_token: Token = .{ .code = 70, .value = .{ .raw = " 42 " } };
    try std.testing.expectEqual(@as(i16, 42), try int_token.int(i16));

    const float_token: Token = .{ .code = 40, .value = .{ .raw = " 12.5 " } };
    try std.testing.expectEqual(@as(f64, 12.5), try float_token.float(f64));

    const bool_token: Token = .{ .code = 290, .value = .{ .raw = "1" } };
    try std.testing.expectEqual(true, try bool_token.boolean());

    const invalid_token: Token = .{ .code = 70, .value = .{ .raw = "abc" } };
    try std.testing.expectError(error.InvalidValue, invalid_token.int(i16));
}
