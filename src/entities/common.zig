const parse = @import("parse");

pub const Vec3 = struct {
    x: f64 = 0,
    y: f64 = 0,
    z: f64 = 0,
};

pub const Error = parse.Parser.Error || error{
    UnexpectedEvent,
    UnexpectedEof,
    InvalidValue,
};

pub fn skip(parser: *parse.Parser) Error!void {
    while (try parser.next()) |event| {
        switch (event) {
            .entity_end, .object_end, .class_end, .table_record_end => return,
            .pair => {},
            else => return error.UnexpectedEvent,
        }
    }

    return error.UnexpectedEof;
}
