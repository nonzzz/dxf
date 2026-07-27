const std = @import("std");

pub const SectionKind = enum {
    header,
    classes,
    tables,
    blocks,
    entities,
    objects,
    thumbnailimage,
    unknown,

    pub fn from_raw(raw: []const u8) SectionKind {
        if (std.mem.eql(u8, raw, "HEADER")) return .header;
        if (std.mem.eql(u8, raw, "CLASSES")) return .classes;
        if (std.mem.eql(u8, raw, "TABLES")) return .tables;
        if (std.mem.eql(u8, raw, "BLOCKS")) return .blocks;
        if (std.mem.eql(u8, raw, "ENTITIES")) return .entities;
        if (std.mem.eql(u8, raw, "OBJECTS")) return .objects;
        if (std.mem.eql(u8, raw, "THUMBNAILIMAGE")) return .thumbnailimage;
        return .unknown;
    }
};

pub const TableKind = enum {
    appid,
    block_record,
    dimstyle,
    layer,
    ltype,
    style,
    ucs,
    view,
    vport,
    unknown,

    pub fn from_raw(raw: []const u8) TableKind {
        if (std.mem.eql(u8, raw, "APPID")) return .appid;
        if (std.mem.eql(u8, raw, "BLOCK_RECORD")) return .block_record;
        if (std.mem.eql(u8, raw, "DIMSTYLE")) return .dimstyle;
        if (std.mem.eql(u8, raw, "LAYER")) return .layer;
        if (std.mem.eql(u8, raw, "LTYPE")) return .ltype;
        if (std.mem.eql(u8, raw, "STYLE")) return .style;
        if (std.mem.eql(u8, raw, "UCS")) return .ucs;
        if (std.mem.eql(u8, raw, "VIEW")) return .view;
        if (std.mem.eql(u8, raw, "VPORT")) return .vport;
        return .unknown;
    }
};

pub const EntityKind = enum {
    line,
    circle,
    arc,
    point,
    text,
    mtext,
    insert,
    polyline,
    vertex,
    seqend,
    lwpolyline,
    ellipse,
    spline,
    hatch,
    solid,
    trace,
    face3d,
    dimension,
    viewport,
    image,
    unknown,

    pub fn from_raw(raw: []const u8) EntityKind {
        if (std.mem.eql(u8, raw, "LINE")) return .line;
        if (std.mem.eql(u8, raw, "CIRCLE")) return .circle;
        if (std.mem.eql(u8, raw, "ARC")) return .arc;
        if (std.mem.eql(u8, raw, "POINT")) return .point;
        if (std.mem.eql(u8, raw, "TEXT")) return .text;
        if (std.mem.eql(u8, raw, "MTEXT")) return .mtext;
        if (std.mem.eql(u8, raw, "INSERT")) return .insert;
        if (std.mem.eql(u8, raw, "POLYLINE")) return .polyline;
        if (std.mem.eql(u8, raw, "VERTEX")) return .vertex;
        if (std.mem.eql(u8, raw, "SEQEND")) return .seqend;
        if (std.mem.eql(u8, raw, "LWPOLYLINE")) return .lwpolyline;
        if (std.mem.eql(u8, raw, "ELLIPSE")) return .ellipse;
        if (std.mem.eql(u8, raw, "SPLINE")) return .spline;
        if (std.mem.eql(u8, raw, "HATCH")) return .hatch;
        if (std.mem.eql(u8, raw, "SOLID")) return .solid;
        if (std.mem.eql(u8, raw, "TRACE")) return .trace;
        if (std.mem.eql(u8, raw, "3DFACE")) return .face3d;
        if (std.mem.eql(u8, raw, "DIMENSION")) return .dimension;
        if (std.mem.eql(u8, raw, "VIEWPORT")) return .viewport;
        if (std.mem.eql(u8, raw, "IMAGE")) return .image;
        return .unknown;
    }
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
