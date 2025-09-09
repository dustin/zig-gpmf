const std = @import("std");
const testing = std.testing;
const zeit = @import("zeit");

pub const tstream = @import("tstream.zig");

comptime {
    if (@import("builtin").is_test) {
        _ = @import("tstream.zig");
        _ = @import("constants.zig");
        _ = @import("gpmf_tests.zig");
    }
}

/// A FourCC is a 4-byte identifier specified by GPMF.
pub const FourCC = [4]u8;

/// True if two FourCCs are equal.
pub inline fn eqFourCC(a: FourCC, b: FourCC) bool {
    return a[0] == b[0] and a[1] == b[1] and a[2] == b[2] and a[3] == b[3];
}

test eqFourCC {
    const a = FourCC{ 'G', 'P', 'M', 'F' };
    const b = FourCC{ 'G', 'P', 'M', 'F' };
    const c = FourCC{ 'D', 'E', 'V', 'C' };

    try testing.expect(eqFourCC(a, b));
    try testing.expect(!eqFourCC(a, c));
}

/// A Value within a GPMF stream.
pub const Value = union(enum) {
    /// A single byte signed integer (-128 to 127)
    b: i8,
    /// A single byte unsigned integer (0 to 255)
    B: u8,
    /// A single byte 'c' style ASCII character string (optionally NULL terminated)
    c: []const u8,
    /// A 64-bit double precision (IEEE 754)
    d: f64,
    /// A 32-bit float (IEEE 754)
    f: f32,
    /// A 32-bit four character key -- FourCC
    F: FourCC,
    /// A 128-bit ID (like UUID)
    G: [16]u8,
    /// A 64-bit signed unsigned number
    j: i64,
    /// A 64-bit unsigned unsigned number
    J: u64,
    /// A 32-bit signed integer
    l: i32,
    /// A 32-bit unsigned integer
    L: u32,
    /// A 32-bit Q Number Q15.16
    q: u32,
    /// A 64-bit Q Number Q31.32
    Q: u64,
    /// A 16-bit signed integer
    s: i16,
    /// A 16-bit unsigned integer
    S: u16,
    /// A UTC Date and Time value
    U: zeit.Instant,
    /// A complex data structure.  The format is a string of characters that describe the data structure.
    complex: struct { fmt: []const u8, data: []Value },
    /// A nested data structure with an identifier.
    nested: struct { fourcc: FourCC, data: []Value },
    /// An unknown data structure
    unknown: struct { charId: u8, a1: usize, a2: i32, stuff: [][]u8 },

    /// Cast a Value to the specified type.
    pub fn as(self: Value, comptime T: type) ConversionError!T {
        return extractValue(T, self);
    }
};

pub const ConversionError = error{ InvalidIntValue, InvalidIntSrc, InvalidFloatSrc, InvalidStringSrc };

pub fn FormatSlice(comptime fmt: []const u8, comptime T: type) type {
    return struct {
        things: T = undefined,

        pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.writeAll("[");
            for (self.things, 0..) |s, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print(fmt, .{s});
            }
            try w.writeAll("]");
        }
    };
}

pub fn formatSlice(comptime fmt: []const u8, things: anytype) FormatSlice(fmt, @TypeOf(things)) {
    return FormatSlice(fmt, @TypeOf(things)){ .things = things };
}

fn safeCast(comptime T: type, v: anytype) ?T {
    return switch (@typeInfo(T)) {
        .int => switch (@typeInfo(@TypeOf(v))) {
            .int => std.math.cast(T, v),
            .float => {
                if (v < @as(@TypeOf(v), @floatFromInt(std.math.minInt(T))) or v > @as(@TypeOf(v), @floatFromInt(std.math.maxInt(T)))) {
                    return null;
                } else {
                    return @intFromFloat(v);
                }
            },
            else => return null,
        },
        .float => switch (@typeInfo(@TypeOf(v))) {
            .int => @intFromFloat(v),
            .float => @floatCast(v),
            else => return null,
        },
        else => return null,
    };
}

fn extractValue(comptime T: type, v: Value) ConversionError!T {
    const extractors = struct {
        fn int(vi: Value) ConversionError!T {
            return switch (vi) {
                .b => std.math.cast(T, vi.b),
                .B => std.math.cast(T, vi.B),
                .d => safeCast(T, vi.d),
                .f => safeCast(T, vi.f),
                .j => std.math.cast(T, vi.j),
                .J => std.math.cast(T, vi.J),
                .l => std.math.cast(T, vi.l),
                .L => std.math.cast(T, vi.L),
                .q => std.math.cast(T, vi.q),
                .Q => std.math.cast(T, vi.Q),
                .s => std.math.cast(T, vi.s),
                .S => std.math.cast(T, vi.S),
                else => return error.InvalidIntSrc,
            } orelse error.InvalidIntValue;
        }
        fn float(vf: Value) ConversionError!T {
            return switch (vf) {
                .b => @floatFromInt(vf.b),
                .B => @floatFromInt(vf.B),
                .d => @floatCast(vf.d),
                .f => @floatCast(vf.f),
                .j => @floatFromInt(vf.j),
                .J => @floatFromInt(vf.J),
                .l => @floatFromInt(vf.l),
                .L => @floatFromInt(vf.L),
                .q => @floatFromInt(vf.q),
                .Q => @floatFromInt(vf.Q),
                .s => @floatFromInt(vf.s),
                .S => @floatFromInt(vf.S),
                else => return error.InvalidFloatSrc,
            };
        }
        fn pointer(pf: Value) ConversionError!T {
            return switch (pf) {
                .c => pf.c,
                .G => &pf.G,
                else => {
                    std.debug.print("Invalid string src: {any}\n", .{pf});
                    return error.InvalidStringSrc;
                },
            };
        }
    };
    switch (@typeInfo(T)) {
        .int => {
            return extractors.int(v);
        },
        .float => {
            return extractors.float(v);
        },
        .pointer => {
            return extractors.pointer(v);
        },
        else => {
            @compileError("Unable to extract '" ++ @typeName(T) ++ "'");
        },
    }
}

const Parser = struct {
    input: *std.Io.Reader,
    alloc: std.mem.Allocator,
    ctype: []const u8,
};

/// A Value representing a parsed GPMF stream.
pub const Parsed = struct {
    arena: *std.heap.ArenaAllocator,
    value: Value,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};

/// Parse a stream of GPMF data into a low-level stream of parsed values.
pub fn parse(allocator: std.mem.Allocator, input: *std.Io.Reader) anyerror!Parsed {
    var arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var p = Parser{ .input = input, .alloc = arena.allocator(), .ctype = "" };
    return .{
        .value = try parseNested(&p),
        .arena = arena,
    };
}

fn parseNested(p: *Parser) anyerror!Value {
    const fcc = try parseFourCC(p.input);
    const t = try p.input.takeByte();
    const ss: usize = @as(usize, @intCast(try p.input.takeByte()));
    const rpt = try p.input.takeInt(u16, .big);
    const vs = try parseValue(p, t, ss, rpt);
    const padding = (4 - ((ss * rpt) % 4)) % 4;
    for (0..padding) |_| {
        _ = p.input.takeByte() catch |err| switch (err) {
            error.EndOfStream => {},
            else => return err,
        };
    }
    if (std.mem.eql(u8, &fcc, "TYPE")) {
        switch (vs[0]) {
            .c => p.ctype = vs[0].c,
            else => {},
        }
    }
    return .{ .nested = .{ .fourcc = fcc, .data = vs } };
}

fn parseFourCC(input: *std.Io.Reader) !FourCC {
    var fcc: FourCC = undefined;
    inline for (0..4) |i| {
        fcc[i] = try input.takeByte();
    }
    return fcc;
}

test parseFourCC {
    var buf: [4]u8 = "GPMF".*;
    var fbs = std.Io.Reader.fixed(&buf);
    const fcc = try parseFourCC(&fbs);
    try testing.expectEqual(fcc, FourCC{ 'G', 'P', 'M', 'F' });
}

fn replicated(p: *Parser, one: usize, l: usize, rpt: u16, t: u8) ![]Value {
    const entries = (l / one) * rpt;
    var a = try p.alloc.alloc(Value, entries);
    for (0..entries) |i| {
        a[i] = try simpleParser(t, p.input);
    }
    return a;
}

fn simpleParser(c: u8, input: *std.Io.Reader) anyerror!Value {
    return switch (c) {
        'b' => .{ .b = try input.takeByteSigned() },
        'B' => .{ .B = try input.takeByte() },
        'd' => .{ .d = @bitCast(try input.takeInt(u64, .big)) },
        'f' => .{ .f = @bitCast(try input.takeInt(u32, .big)) },
        'F' => .{ .F = try parseFourCC(input) },
        'j' => .{ .j = try input.takeInt(i64, .big) },
        'J' => .{ .J = try input.takeInt(u64, .big) },
        'l' => .{ .l = try input.takeInt(i32, .big) },
        'L' => .{ .L = try input.takeInt(u32, .big) },
        'q' => .{ .q = try input.takeInt(u32, .big) },
        'Q' => .{ .Q = try input.takeInt(u64, .big) },
        's' => .{ .s = try input.takeInt(i16, .big) },
        'S' => .{ .S = try input.takeInt(u16, .big) },
        else => std.debug.panic("no simple parser for: {c}\n", .{c}),
    };
}

test simpleParser {
    const Example = struct {
        c: u8,
        bytes: []const u8,
        value: Value,
    };

    const staticExamples = [_]Example{
        .{ .c = 'F', .bytes = &[4]u8{ 71, 80, 77, 70 }, .value = .{ .F = [4]u8{ 71, 80, 77, 70 } } },
        .{ .c = 'f', .bytes = &[4]u8{ 64, 73, 15, 219 }, .value = .{ .f = 3.1415927 } },
        .{ .c = 'L', .bytes = &[4]u8{ 0, 0, 0, 42 }, .value = .{ .L = 42 } },
        .{ .c = 'l', .bytes = &[4]u8{ 255, 255, 255, 214 }, .value = .{ .l = -42 } },
        .{ .c = 'B', .bytes = &[1]u8{255}, .value = .{ .B = 255 } },
        .{ .c = 'b', .bytes = &[1]u8{214}, .value = .{ .b = -42 } },
        .{ .c = 'S', .bytes = &[2]u8{ 0, 42 }, .value = .{ .S = 42 } },
        .{ .c = 's', .bytes = &[2]u8{ 0, 42 }, .value = .{ .s = 42 } },
        .{ .c = 'd', .bytes = &[8]u8{ 64, 9, 33, 251, 84, 68, 45, 24 }, .value = .{ .d = 3.141592653589793 } },
        .{ .c = 'j', .bytes = &[8]u8{ 0, 0, 0, 0, 0, 0, 0, 42 }, .value = .{ .j = 42 } },
        .{ .c = 'J', .bytes = &[8]u8{ 0, 0, 0, 0, 0, 0, 0, 42 }, .value = .{ .J = 42 } },
        .{ .c = 'q', .bytes = &[4]u8{ 0, 0, 0, 42 }, .value = .{ .q = 42 } },
        .{ .c = 'Q', .bytes = &[8]u8{ 0, 0, 0, 0, 0, 0, 0, 42 }, .value = .{ .Q = 42 } },
    };

    for (staticExamples) |example| {
        var fbs = std.Io.Reader.fixed(example.bytes);

        const result = try simpleParser(example.c, &fbs);
        try std.testing.expectEqual(example.value, result);
    }
}

fn parseValue(p: *Parser, t: u8, ss: usize, rpt: u16) anyerror![]Value {
    return switch (t) {
        'b' => replicated(p, 1, ss, rpt, t),
        'B' => replicated(p, 1, ss, rpt, t),
        'c' => {
            var a = try p.alloc.alloc(Value, rpt);
            for (0..rpt) |i| {
                var buf = try p.alloc.alloc(u8, ss);
                for (0..ss) |j| {
                    buf[j] = try p.input.takeByte();
                }
                a[i] = .{ .c = buf };
            }
            return a;
        },
        'd' => replicated(p, 8, ss, rpt, t),
        'f' => replicated(p, 4, ss, rpt, t),
        'F' => replicated(p, 4, ss, rpt, t),
        'G' => {
            var a = try p.alloc.alloc(Value, rpt);
            for (0..rpt) |i| {
                var buf: [16]u8 = undefined;
                inline for (0..16) |j| {
                    buf[j] = try p.input.takeByte();
                }
                a[i] = .{ .G = buf };
            }
            return a;
        },
        'j' => replicated(p, 8, ss, rpt, t),
        'J' => replicated(p, 8, ss, rpt, t),
        'l' => replicated(p, 4, ss, rpt, t),
        'L' => replicated(p, 4, ss, rpt, t),
        'q' => replicated(p, 4, ss, rpt, t),
        'Q' => replicated(p, 8, ss, rpt, t),
        's' => replicated(p, 2, ss, rpt, t),
        'S' => replicated(p, 2, ss, rpt, t),
        'U' => {
            var a = try p.alloc.alloc(Value, rpt);
            for (0..rpt) |i| {
                var buf: [16]u8 = undefined;
                inline for (0..16) |j| {
                    buf[j] = try p.input.takeByte();
                }
                a[i] = .{ .U = try zeit.instant(.{}) };
                const inst = try zeit.instant(.{
                    .source = .{
                        .iso8601 = try convertTimestamp(p.alloc, &buf),
                    },
                });
                a[i] = .{ .U = inst };
            }
            return a;
        },
        '?' => parseComplex(p, ss, rpt),
        0 => {
            var buf: [8192]u8 = undefined;
            var inin = std.Io.Reader.Limited.init(p.input, std.Io.Limit.limited(@intCast(ss * rpt)), &buf);
            var pin = Parser{ .input = &inin.interface, .alloc = p.alloc, .ctype = p.ctype };

            var a = try p.alloc.alloc(Value, rpt);
            var n: u32 = 0;
            for (0..rpt) |i| {
                const parsed = parseNested(&pin) catch |err| switch (err) {
                    error.EndOfStream => {
                        a = a[0..n];
                        return a;
                    },
                    else => return err,
                };
                a[i] = parsed;
                n = n + 1;
            }
            return a;
        },
        else => {
            std.debug.print("no value parser for: {c} {d}\n", .{ t, t });
            return error.InvalidType;
        },
    };
}

test "parseValue error cases" {
    // Test invalid type character
    var input = [_]u8{0};
    var fbs = std.Io.Reader.fixed(&input);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var p = Parser{
        .input = &fbs,
        .alloc = arena.allocator(),
        .ctype = "",
    };

    // This should panic with invalid type - you might want to change the implementation
    // to return an error instead of panicking
    try testing.expectError(error.InvalidType, parseValue(&p, 'X', 1, 1));
}

fn parseComplex(p: *Parser, _: usize, rpt: u16) anyerror![]Value {
    var a = try p.alloc.alloc(Value, rpt);
    for (0..rpt) |r| {
        var vals = try p.alloc.alloc(Value, p.ctype.len);
        for (p.ctype, 0..) |f, i| {
            vals[i] = try simpleParser(f, p.input);
        }
        a[r] = .{ .complex = .{ .fmt = p.ctype, .data = vals } };
    }

    return a;
}

fn convertTimestamp(allocator: std.mem.Allocator, ts: []const u8) ![]u8 {
    // Example input format: "241109183315.400"
    if (ts.len < 14) {
        return error.InputTooShort;
    }
    if (ts[12] != '.') {
        return error.InvalidFormat;
    }

    // Parse needed slices:
    const yy = ts[0..2];
    const mm = ts[2..4];
    const dd = ts[4..6];
    const HH = ts[6..8];
    const MM = ts[8..10];
    const SS = ts[10..12];
    const fractional = ts[13..];

    const out = try std.fmt.allocPrint(
        allocator,
        "20{s}-{s}-{s}T{s}:{s}:{s}.{s}Z",
        .{ yy, mm, dd, HH, MM, SS, fractional },
    );

    return out;
}

test convertTimestamp {
    const allocator = std.testing.allocator;
    const input = "241109183315.400";
    const want = "2024-11-09T18:33:15.400Z";
    const result = try convertTimestamp(allocator, input);
    defer allocator.free(result);

    try testing.expectEqualStrings(result, want);
}
