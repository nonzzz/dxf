const parse = @import("parse");

pub const Vec3 = struct {
    x: f64 = 0,
    y: f64 = 0,
    z: f64 = 0,
};

pub const ReadError = parse.Parser.Error || error{
    UnexpectedEvent,
    UnexpectedEof,
    InvalidValue,
};

pub fn Sink(comptime T: type, comptime E: type) type {
    return struct {
        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            emit: *const fn (*anyopaque, T) E!void,
        };

        pub fn emit(self: @This(), value: T) E!void {
            return self.vtable.emit(self.ptr, value);
        }
    };
}

pub fn skip(parser: *parse.Parser) ReadError!void {
    while (try parser.next()) |event| {
        switch (event) {
            .entity_end, .object_end, .class_end, .table_record_end => return,
            .pair => {},
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}
