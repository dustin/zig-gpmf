const std = @import("std");
const testing = std.testing;

const FourCC = [4]u8;

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

const Value = union(enum) {
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
    U: [16]u8,
    complex: struct { type: []u8, data: []Value },
    nested: struct { fourcc: FourCC, data: []Value },
    unknown: struct { charId: u8, a1: usize, a2: i32, stuff: [][]u8 },
};

const Parser = struct {
    input: std.io.AnyReader,
    alloc: std.mem.Allocator,
    ctype: []const u8,
};

pub fn parse(allocator: std.mem.Allocator, input: std.io.AnyReader) anyerror!Value {
    var p = Parser{ .input = input, .alloc = allocator, .ctype = "" };
    return try parseNested(&p);
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
    // value from TYPE is { types.Value{ .c = { 70, 102 } } }
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
    std.debug.print("Parsed {s}\n", .{fcc});
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
                a[i] = .{ .U = buf };
            }
            return a;
        },
        '?' => parseComplex(p, ss, rpt),
        0 => {
            var a = try p.alloc.alloc(Value, rpt);
            var n: u32 = 0;
            for (0..rpt) |i| {
                const parsed = parseNested(p) catch |err| switch (err) {
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
        else => unreachable,
    };
}

fn parseComplex(p: *Parser, _: usize, rpt: u16) anyerror![]Value {
    var a = std.ArrayList(Value).init(p.alloc);
    for (0..rpt) |_| {
        for (p.ctype) |f| {
            try a.append(try simpleParser(f, p.input));
        }
    }
    return a.items;
}

test parseFourCC {
    var buf: [4]u8 = "GPMF".*;
    var fbs = std.io.fixedBufferStream(&buf);
    const fcc = try parseFourCC(fbs.reader().any());
    try testing.expectEqual(fcc, FourCC{ 'G', 'P', 'M', 'F' });
}
