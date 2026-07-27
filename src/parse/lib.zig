const event = @import("./event.zig");
const kind = @import("./kind.zig");
const diagnostic = @import("./diagnostic.zig");

pub const Parser = @import("./parse.zig");
pub const Event = event.Event;
pub const SectionKind = kind.SectionKind;
pub const TableKind = kind.TableKind;
pub const EntityKind = kind.EntityKind;
pub const Marker = kind.Marker;
pub const Options = diagnostic.Options;
pub const Diagnostics = diagnostic.Diagnostics;
pub const Diagnostic = diagnostic.Diagnostic;
pub const Severity = diagnostic.Severity;
pub const DiagnosticCode = diagnostic.DiagnosticCode;

test {
    _ = Parser;
    _ = Event;
    _ = SectionKind;
    _ = TableKind;
    _ = EntityKind;
    _ = Marker;
    _ = Options;
    _ = Diagnostics;
    _ = Diagnostic;
    _ = Severity;
    _ = DiagnosticCode;
}
