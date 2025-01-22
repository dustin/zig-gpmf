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

fn replicated(p: *Parser, one: usize, l: usize, rpt: u16, p1: fn (input: std.io.AnyReader) anyerror!Value) ![]Value {
    const entries = (l / one) * rpt;
    var a = try p.alloc.alloc(Value, entries);
    for (0..entries) |i| {
        a[i] = try p1(p.input);
    }
    return a;
}

fn parse_b(input: std.io.AnyReader) anyerror!Value {
    return .{ .b = try input.readByteSigned() };
}

fn parse_B(input: std.io.AnyReader) anyerror!Value {
    return .{ .B = try input.readByte() };
}

fn parse_d(input: std.io.AnyReader) anyerror!Value {
    return .{ .d = @bitCast(try input.readInt(u64, .big)) };
}

fn parse_f(input: std.io.AnyReader) anyerror!Value {
    return .{ .f = @bitCast(try input.readInt(u32, .big)) };
}

fn parse_F(input: std.io.AnyReader) anyerror!Value {
    return .{ .F = try parseFourCC(input) };
}

fn parse_j(input: std.io.AnyReader) anyerror!Value {
    return .{ .j = try input.readInt(i64, .big) };
}

fn parse_J(input: std.io.AnyReader) anyerror!Value {
    return .{ .J = try input.readInt(u64, .big) };
}

fn parse_l(input: std.io.AnyReader) anyerror!Value {
    return .{ .l = try input.readInt(i32, .big) };
}

fn parse_L(input: std.io.AnyReader) anyerror!Value {
    return .{ .L = try input.readInt(u32, .big) };
}

fn parse_q(input: std.io.AnyReader) anyerror!Value {
    return .{ .q = try input.readInt(u32, .big) };
}

fn parse_Q(input: std.io.AnyReader) anyerror!Value {
    return .{ .Q = try input.readInt(u64, .big) };
}

fn parse_s(input: std.io.AnyReader) anyerror!Value {
    return .{ .s = try input.readInt(i16, .big) };
}

fn parse_S(input: std.io.AnyReader) anyerror!Value {
    return .{ .S = try input.readInt(u16, .big) };
}

fn parseValue(p: *Parser, t: u8, ss: usize, rpt: u16) anyerror![]Value {
    return switch (t) {
        'b' => replicated(p, 1, ss, rpt, parse_b),
        'B' => replicated(p, 1, ss, rpt, parse_B),
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
        'd' => replicated(p, 8, ss, rpt, parse_d),
        'f' => replicated(p, 4, ss, rpt, parse_f),
        'F' => replicated(p, 4, ss, rpt, parse_F),
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
        'j' => replicated(p, 8, ss, rpt, parse_j),
        'J' => replicated(p, 8, ss, rpt, parse_J),
        'l' => replicated(p, 4, ss, rpt, parse_l),
        'L' => replicated(p, 4, ss, rpt, parse_L),
        'q' => replicated(p, 4, ss, rpt, parse_q),
        'Q' => replicated(p, 8, ss, rpt, parse_Q),
        's' => replicated(p, 2, ss, rpt, parse_s),
        'S' => replicated(p, 2, ss, rpt, parse_S),
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
        //  {
        //     var a = try p.alloc.alloc(Value, 1);
        //     a[0] = .{ .unknown = .{ .charId = t, .a1 = ss, .a2 = rpt, .stuff = undefined } };
        //     return a;
        // },
    };
}

fn parseComplex(p: *Parser, _: usize, rpt: u16) anyerror![]Value {
    var a = try p.alloc.alloc(Value, rpt);
    // TODO:  This is putting stuff in the wrong place.
    for (0..rpt) |i| {
        for (p.ctype) |f| {
            a[i] = switch (f) {
                'F' => try parse_F(p.input),
                'f' => try parse_f(p.input),
                'L' => try parse_L(p.input),
                'l' => try parse_l(p.input),
                'B' => try parse_B(p.input),
                'b' => try parse_b(p.input),
                'S' => try parse_S(p.input),
                's' => try parse_s(p.input),
                else => std.debug.panic("unhandled complex type: {c}\n", .{p.ctype[i]}),
            };
        }
    }
    return a;
}

test parseFourCC {
    var buf: [4]u8 = "GPMF".*;
    var fbs = std.io.fixedBufferStream(&buf);
    const fcc = try parseFourCC(fbs.reader().any());
    try testing.expectEqual(fcc, FourCC{ 'G', 'P', 'M', 'F' });
}
