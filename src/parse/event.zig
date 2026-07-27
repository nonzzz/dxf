const tokenizer_mod = @import("tokenizer");
const Tokenizer = tokenizer_mod.Tokenizer;
const kind = @import("./kind.zig");

pub const Event = union(enum) {
    /// Borrowed section name. Valid until the parser advances.
    section_start: SectionStart,
    section_end: End,

    /// Borrowed table name. Valid until the parser advances.
    table_start: TableStart,
    table_end: End,

    /// Borrowed table record kind. Valid until the parser advances.
    table_record_start: TableRecordStart,
    table_record_end: End,

    block_start: BlockStart,
    block_end: End,

    /// Borrowed class kind. Valid until the parser advances.
    class_start: ClassStart,
    class_end: End,

    /// Borrowed entity kind. Valid until the parser advances.
    entity_start: EntityStart,
    entity_end: End,

    /// Borrowed object kind. Valid until the parser advances.
    object_start: ObjectStart,
    object_end: End,

    /// Original tokenizer token. Any borrowed value follows tokenizer lifetime.
    pair: Tokenizer.Token,
};

pub const SectionStart = struct {
    kind: kind.SectionKind,
    name: []const u8,
    loc: Tokenizer.Loc,
};

pub const TableStart = struct {
    kind: kind.TableKind,
    name: []const u8,
    loc: Tokenizer.Loc,
};

pub const TableRecordStart = struct {
    table: kind.TableKind,
    kind: []const u8,
    loc: Tokenizer.Loc,
};

pub const BlockStart = struct {
    loc: Tokenizer.Loc,
};

pub const ClassStart = struct {
    kind: []const u8,
    loc: Tokenizer.Loc,
};

pub const EntityStart = struct {
    kind: kind.EntityKind,
    name: []const u8,
    loc: Tokenizer.Loc,
};

pub const ObjectStart = struct {
    kind: []const u8,
    loc: Tokenizer.Loc,
};

pub const End = struct {
    loc: Tokenizer.Loc,
};
