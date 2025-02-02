const std = @import("std");
const gpmf = @import("gpmf");
const tstream = gpmf.tstream;

fn toKML(alloc: std.mem.Allocator, r: std.io.AnyReader, w: std.io.AnyWriter) !void {
    var readings = std.MultiArrayList(tstream.GPSReading){};
    defer readings.deinit(alloc);

    while (true) {
        const parsed = gpmf.parse(alloc, r) catch |err| switch (err) {
            error.EndOfStream => break,
            else => {
                std.debug.print("Error parsing: {any}", .{err});
                unreachable;
            },
        };
        defer parsed.deinit();

        const ts = try tstream.mkTelemetryStream(alloc, parsed);
        defer ts.deinit();

        var gpses = try ts.gpsReadings(alloc);
        defer gpses.deinit();
        try readings.ensureUnusedCapacity(alloc, gpses.items.len);
        for (gpses.items) |g| {
            readings.appendAssumeCapacity(g);
        }
    }

    try w.print("<?xml version=\"1.0\"?>\n", .{});

    const xml = Tag{ .name = "kml", .attrs = &.{Attribute{ .k = "xmlns", .v = "http://www.opengis.net/kml/2.2" }} };
    try xml.start(w);
    defer xml.end(w);

    const doc = Tag{ .name = "Document" };
    try doc.start(w);
    defer doc.end(w);

    try immediate(w, "name", &.{}, "GoPro Path", .{});
    try immediate(w, "description", &.{}, "Captured at {s}", .{"sometime"});
    {
        const style = Tag{ .name = "Style", .attrs = &.{Attribute{ .k = "id", .v = "yellowLineGreenPoly" }} };
        try style.start(w);
        defer style.end(w);
        {
            const ls = Tag{ .name = "LineStyle" };
            try ls.start(w);
            defer ls.end(w);
            try immediate(w, "color", &.{}, "7f00ffff", .{});
            try immediate(w, "width", &.{}, "4", .{});
        }
        {
            const ls = Tag{ .name = "PolyStyle" };
            try ls.start(w);
            defer ls.end(w);
            try immediate(w, "color", &.{}, "7f00ff00", .{});
        }
    }
    {
        const pl = Tag{ .name = "Placemark" };
        try pl.start(w);
        defer pl.end(w);
        try immediate(w, "name", &.{}, "GoPro Path", .{});
        try immediate(w, "description", &.{}, "Interesting stuff here", .{});
        try immediate(w, "styleUrl", &.{Attribute{ .k = "url", .v = "#yellowLineGreenPoly" }}, "", .{});

        const ls = Tag{ .name = "LineString" };
        try ls.start(w);
        defer ls.end(w);

        try immediate(w, "extrude", &.{}, "1", .{});
        try immediate(w, "tessellate", &.{}, "1", .{});
        try immediate(w, "altitudeMode", &.{}, "relative", .{});

        {
            const coords = Tag{ .name = "coordinates" };
            try coords.start(w);
            defer coords.end(w);
            for (readings.items(.lon), readings.items(.lat), readings.items(.alt)) |lon, lat, alt| {
                try w.print("{d},{d},{d}\n", .{ lon, lat, alt });
            }
        }
    }
}

fn immediate(w: std.io.AnyWriter, name: []const u8, attrs: []const Attribute, comptime fmt: []const u8, args: anytype) !void {
    const tag = Tag{ .name = name, .attrs = attrs };
    try tag.start(w);
    try w.print(fmt, args);
    defer tag.end(w);
}

const Attribute: type = struct {
    k: []const u8,
    v: []const u8,
};

const Tag: type = struct {
    name: []const u8,
    attrs: []const Attribute = &.{},

    pub fn start(self: @This(), w: std.io.AnyWriter) std.io.AnyWriter.Error!void {
        try w.print("<{s}", .{self.name});
        for (self.attrs) |attr| {
            try w.print(" {s}=\"{s}\"", .{ attr.k, attr.v });
        }
        try w.print(">", .{});
    }

    pub fn end(self: @This(), w: std.io.AnyWriter) void {
        w.print("</{s}>", .{self.name}) catch return;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch return;
    defer std.process.argsFree(allocator, args);

    var infile = try std.fs.openFileAbsolute(args[1], std.fs.File.OpenFlags{});
    defer infile.close();

    return toKML(allocator, infile.reader().any(), std.io.getStdOut().writer().any());
}
