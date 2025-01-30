const std = @import("std");
const testing = std.testing;
const zeit = @import("zeit");

pub const FourCC = [4]u8;

fn fourcc(s: []const u8) FourCC {
    return [4]u8{ s[0], s[1], s[2], s[3] };
}

pub const DEVC: FourCC = fourcc("DEVC");
pub const DVID: FourCC = fourcc("DVID");
pub const DVNM: FourCC = fourcc("DVNM");
pub const STRM: FourCC = fourcc("STRM");
pub const STMP: FourCC = fourcc("STMP");
pub const TSMP: FourCC = fourcc("TSMP");
pub const STNM: FourCC = fourcc("STNM");
pub const AALP: FourCC = fourcc("AALP");
pub const ACCL: FourCC = fourcc("ACCL");
pub const SCEN: FourCC = fourcc("SCEN");
pub const SNOW: FourCC = fourcc("SNOW");
pub const URBA: FourCC = fourcc("URBA");
pub const INDO: FourCC = fourcc("INDO");
pub const WATR: FourCC = fourcc("WATR");
pub const VEGE: FourCC = fourcc("VEGE");
pub const BEAC: FourCC = fourcc("BEAC");
pub const URBN: FourCC = fourcc("URBN");
pub const INDR: FourCC = fourcc("INDR");
pub const FACE: FourCC = fourcc("FACE");
pub const GPSF: FourCC = fourcc("GPSF");
pub const GPSU: FourCC = fourcc("GPSU");
pub const GPSP: FourCC = fourcc("GPSP");
pub const GPS5: FourCC = fourcc("GPS5");
pub const GPS9: FourCC = fourcc("GPS9");
pub const SCAL: FourCC = fourcc("SCAL");
pub const TMPC: FourCC = fourcc("TMPC");
pub const GYRO: FourCC = fourcc("GYRO");
pub const UNIT: FourCC = fourcc("UNIT");
pub const SIUN: FourCC = fourcc("SIUN");

pub inline fn eqFourCC(a: FourCC, b: FourCC) bool {
    return a[0] == b[0] and a[1] == b[1] and a[2] == b[2] and a[3] == b[3];
}

test "fourcc" {
    try testing.expectEqual("GPMF".*, FourCC{ 'G', 'P', 'M', 'F' });
}

// Type Char	Definition	typedef	Comment
// b	single byte signed integer	int8_t	-128 to 127
// B	single byte unsigned integer	uint8_t	0 to 255
// c	single byte 'c' style ASCII character string	char	Optionally NULL terminated - size/repeat sets the length
// d	64-bit double precision (IEEE 754)	double
// f	32-bit float (IEEE 754)	float
// F	32-bit four character key -- FourCC	char fourcc[4]
// G	128-bit ID (like UUID)	uint8_t guid[16]
// j	64-bit signed unsigned number	int64_t
// J	64-bit unsigned unsigned number	uint64_t
// l	32-bit signed integer	int32_t
// L	32-bit unsigned integer	uint32_t
// q	32-bit Q Number Q15.16	uint32_t	16-bit integer (A) with 16-bit fixed point (B) for A.B value (range -32768.0 to 32767.99998)
// Q	64-bit Q Number Q31.32	uint64_t	32-bit integer (A) with 32-bit fixed point (B) for A.B value.
// s	16-bit signed integer	int16_t	-32768 to 32768
// S	16-bit unsigned integer	uint16_t	0 to 65536
// U	UTC Date and Time string	char utcdate[16]	Date + UTC Time format yymmddhhmmss.sss - (years 20xx covered)
// ?	data structure is complex	TYPE	Structure is defined with a preceding TYPE
// null	Nested metadata	uint32_t	The data within is GPMF structured KLV data

pub const Value = union(enum) {
    b: i8,
    B: u8,
    c: []const u8,
    d: f64,
    f: f32,
    F: FourCC,
    G: [16]u8,
    j: i64,
    J: u64,
    l: i32,
    L: u32,
    q: u32,
    Q: u64,
    s: i16,
    S: u16,
    U: zeit.Instant,
    complex: struct { fmt: []const u8, data: []Value },
    nested: struct { fourcc: FourCC, data: []Value },
    unknown: struct { charId: u8, a1: usize, a2: i32, stuff: [][]u8 },

    pub fn as(self: Value, comptime T: type) ConversionError!T {
        return extractValue(T, self);
    }
};

pub const ConversionError = error{ InvalidIntSrc, InvalidFloatSrc, InvalidStringSrc };

fn extractValue(comptime T: type, v: Value) ConversionError!T {
    const extractors = struct {
        fn Int(vi: Value) ConversionError!T {
            return switch (vi) {
                .b => @intCast(vi.b),
                .B => @intCast(vi.B),
                .d => @intFromFloat(vi.d),
                .f => @intFromFloat(vi.f),
                .j => @intCast(vi.j),
                .J => @intCast(vi.J),
                .l => @intCast(vi.l),
                .L => @intCast(vi.L),
                .q => @intCast(vi.q),
                .Q => @intCast(vi.Q),
                .s => @intCast(vi.s),
                .S => @intCast(vi.S),
                else => return error.InvalidIntSrc,
            };
        }
        fn Float(vf: Value) ConversionError!T {
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
        fn Pointer(pf: Value) ConversionError!T {
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
        .Int => {
            return extractors.Int(v);
        },
        .Float => {
            return extractors.Float(v);
        },
        .Pointer => {
            return extractors.Pointer(v);
        },
        else => {
            @compileError("Unable to extract '" ++ @typeName(T) ++ "'");
        },
    }
}

const Parser = struct {
    input: std.io.AnyReader,
    alloc: std.mem.Allocator,
    ctype: []const u8,
};

pub const Parsed = struct {
    arena: *std.heap.ArenaAllocator,
    value: Value,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};

pub fn parse(allocator: std.mem.Allocator, input: std.io.AnyReader) anyerror!Parsed {
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
    const t = try p.input.readByte();
    const ss: usize = @as(usize, @intCast(try p.input.readByte()));
    const rpt = try p.input.readInt(u16, .big);
    const vs = try parseValue(p, t, ss, rpt);
    const padding = (4 - ((ss * rpt) % 4)) % 4;
    for (0..padding) |_| {
        _ = p.input.readByte() catch |err| switch (err) {
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

fn parseFourCC(input: std.io.AnyReader) !FourCC {
    var fcc: FourCC = undefined;
    inline for (0..4) |i| {
        fcc[i] = try input.readByte();
    }
    return fcc;
}

fn replicated(p: *Parser, one: usize, l: usize, rpt: u16, t: u8) ![]Value {
    const entries = (l / one) * rpt;
    var a = try p.alloc.alloc(Value, entries);
    for (0..entries) |i| {
        a[i] = try simpleParser(t, p.input);
    }
    return a;
}

fn simpleParser(c: u8, input: std.io.AnyReader) anyerror!Value {
    return switch (c) {
        'b' => .{ .b = try input.readByteSigned() },
        'B' => .{ .B = try input.readByte() },
        'd' => .{ .d = @bitCast(try input.readInt(u64, .big)) },
        'f' => .{ .f = @bitCast(try input.readInt(u32, .big)) },
        'F' => .{ .F = try parseFourCC(input) },
        'j' => .{ .j = try input.readInt(i64, .big) },
        'J' => .{ .J = try input.readInt(u64, .big) },
        'l' => .{ .l = try input.readInt(i32, .big) },
        'L' => .{ .L = try input.readInt(u32, .big) },
        'q' => .{ .q = try input.readInt(u32, .big) },
        'Q' => .{ .Q = try input.readInt(u64, .big) },
        's' => .{ .s = try input.readInt(i16, .big) },
        'S' => .{ .S = try input.readInt(u16, .big) },
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
        var fbs = std.io.fixedBufferStream(example.bytes);

        const result = try simpleParser(example.c, fbs.reader().any());
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
                    buf[j] = try p.input.readByte();
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
                    buf[j] = try p.input.readByte();
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
                    buf[j] = try p.input.readByte();
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
            var inin = std.io.limitedReader(p.input, @intCast(ss * rpt));
            var pin = Parser{ .input = inin.reader().any(), .alloc = p.alloc, .ctype = p.ctype };

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
        else => std.debug.panic("no value parser for: {c} {d}\n", .{ t, t }),
    };
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

test parseFourCC {
    var buf: [4]u8 = "GPMF".*;
    var fbs = std.io.fixedBufferStream(&buf);
    const fcc = try parseFourCC(fbs.reader().any());
    try testing.expectEqual(fcc, FourCC{ 'G', 'P', 'M', 'F' });
}

pub fn convertTimestamp(allocator: std.mem.Allocator, ts: []const u8) ![]u8 {
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
