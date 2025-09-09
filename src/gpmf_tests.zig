const std = @import("std");
const testing = std.testing;
const marble = @import("marble");
const zigthesis = @import("zigthesis");
const gpmf = @import("gpmf.zig");

fn castUnion(comptime T: type, from: anytype) T {
    if (@typeInfo(T) != .@"union") {
        @compileError("destination type must be a union for castUnion");
    }
    if (@typeInfo(@TypeOf(from)) != .@"union") {
        @compileError("source type must be a union for castUnion");
    }
    const info = @typeInfo(@TypeOf(from)).@"union";
    inline for (info.fields) |field| {
        if (std.meta.activeTag(from) == @field(std.meta.Tag(@TypeOf(from)), field.name)) {
            return @unionInit(T, field.name, @field(from, field.name));
        }
    }
    unreachable;
}

/// A test subset of Value containing only basic numeric variants.
const TestValue = union(enum) {
    b: i8,
    B: u8,
    j: i64,
    J: u64,
    l: i32,
    L: u32,
    q: u32,
    Q: u64,
    s: i16,
    S: u16,

    /// Convert a TestValue into a regular Value.
    pub fn toValue(self: TestValue) gpmf.Value {
        return castUnion(gpmf.Value, self);
    }
};

const ValueConversionTest = struct {
    value: gpmf.Value,

    pub fn transformTob(self: *@This()) void {
        self.value = .{ .b = self.value.as(i8) catch return };
    }

    pub fn transformToB(self: *@This()) void {
        self.value = .{ .B = self.value.as(u8) catch return };
    }

    pub fn transformTos(self: *@This()) void {
        self.value = .{ .s = self.value.as(i16) catch return };
    }

    pub fn transformToS(self: *@This()) void {
        self.value = .{ .S = self.value.as(u16) catch return };
    }

    pub fn transformTol(self: *@This()) void {
        self.value = .{ .l = self.value.as(i32) catch return };
    }

    pub fn transformToL(self: *@This()) void {
        self.value = .{ .L = self.value.as(u32) catch return };
    }

    pub fn transformToQ(self: *@This()) void {
        self.value = .{ .q = self.value.as(u32) catch return };
    }

    pub fn transformToJ(self: *@This()) void {
        self.value = .{ .J = self.value.as(u64) catch return };
    }

    pub fn check(_: *@This(), orig: gpmf.Value, transformed: gpmf.Value) bool {
        return (orig.as(i65) catch return false) == (transformed.as(i65) catch return false);
    }

    pub fn execute(self: *@This()) gpmf.Value {
        return self.value;
    }
};

fn runConversionTest(v: TestValue) bool {
    var t = ValueConversionTest{ .value = v.toValue() };
    return marble.run(ValueConversionTest, &t, std.testing.allocator, .{}) catch false;
}

test "Value Conversion Metamorphic Property Test" {
    // try zigthesis.falsifyWith(runConversionTest, "conversion tests", .{ .max_iterations = 10000, .onError = zigthesis.failOnError });
}

test "Value conversion examples" {
    // Integer conversions
    const int_val = gpmf.Value{ .l = 42 };
    try testing.expectEqual(@as(i32, 42), try int_val.as(i32));
    try testing.expectEqual(@as(i16, 42), try int_val.as(i16));
    try testing.expectEqual(@as(f32, 42.0), try int_val.as(f32));

    // Float conversions
    const float_val = gpmf.Value{ .f = 3.14 };
    try testing.expectEqual(@as(f32, 3.14), try float_val.as(f32));
    try testing.expectEqual(@as(u8, 3), try float_val.as(u8));

    // String conversion
    const str_val = gpmf.Value{ .c = "test" };
    try testing.expectEqualStrings("test", try str_val.as([]const u8));

    // Error cases
    const bad_int = gpmf.Value{ .c = "not a number" };
    try testing.expectError(error.InvalidIntSrc, bad_int.as(i32));
}

test "parse invalid GPMF data" {
    const allocator = testing.allocator;

    // Test cases with invalid data
    const TestCase = struct {
        name: []const u8,
        data: []const u8,
        expected_error: anyerror,
    };

    const test_cases = [_]TestCase{
        .{
            .name = "empty buffer",
            .data = &[_]u8{},
            .expected_error = error.EndOfStream,
        },
        .{
            .name = "incomplete FourCC",
            .data = &[_]u8{ 'G', 'P', 'M' }, // Missing last character
            .expected_error = error.EndOfStream,
        },
        .{
            .name = "truncated after type",
            .data = &[_]u8{ 'G', 'P', 'M', 'F', 'L' }, // Missing size and repeat count
            .expected_error = error.EndOfStream,
        },
        .{
            .name = "truncated data",
            .data = &[_]u8{ 'G', 'P', 'M', 'F', 'L', 4, 0, 2, 0 }, // Claims 2 L-type values but has no data
            .expected_error = error.EndOfStream,
        },
    };

    for (test_cases) |tc| {
        var fbs = std.Io.Reader.fixed(tc.data);
        const result = gpmf.parse(allocator, &fbs);
        try testing.expectError(tc.expected_error, result);
    }
}
