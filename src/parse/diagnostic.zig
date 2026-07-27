const tokenizer_mod = @import("tokenizer");
const Tokenizer = tokenizer_mod.Tokenizer;

pub const Options = struct {
    /// When true, structural DXF boundary problems are returned as errors.
    /// When false, the parser emits diagnostics and preserves input as events
    /// where possible.
    strict: bool = true,
    diagnostics: ?Diagnostics = null,
};

pub const Diagnostics = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        emit: *const fn (*anyopaque, Diagnostic) void,
    };

    pub fn emit(self: Diagnostics, diagnostic: Diagnostic) void {
        self.vtable.emit(self.ptr, diagnostic);
    }
};

pub const Diagnostic = struct {
    severity: Severity,
    code: DiagnosticCode,
    loc: Tokenizer.Loc,
};

pub const Severity = enum {
    warning,
    err,
};

pub const DiagnosticCode = enum {
    nested_section,
    unexpected_endsec,
    unexpected_endtab,
    unexpected_endblk,
    unexpected_table,
    unexpected_block,
    unexpected_root_record,
    eof_before_endsec,
    eof_before_endtab,
    eof_before_endblk,
};
