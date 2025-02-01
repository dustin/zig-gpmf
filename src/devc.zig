const std = @import("std");
const gpmf = @import("gpmf.zig");
const zeit = @import("zeit");
const constants = @import("constants.zig");

/// A 3D vector.
pub const XYZ = struct {
    x: f32,
    y: f32,
    z: f32,
};

/// Temperature compensated XYZ
pub const TempXYX = struct {
    temp: f32,
    vals: []XYZ,
};

/// Location of a face in an image.
pub const Face = struct {
    id: i32,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    /// Confidence of a smile detection.
    smile: f32,
};

/// A GPS reading.
/// This may be from a GPS5 or GPS9 reading.
pub const GPSReading = struct {
    lat: f64,
    lon: f64,
    alt: f64,
    speed2d: f64,
    speed3d: f64,
    time: zeit.Instant,
    dop: f64,
    fix: u32,
};

/// Audio levels.
pub const AudioLevel = struct {
    rms: []f32,
    peak: []f32,
};

const Location = enum {
    Snow,
    Urban,
    Indoor,
    Water,
    Vegetation,
    Beach,
};

const locMap = std.static_string_map.StaticStringMap(Location).initComptime(&.{
    .{ "SNOW", .Snow },
    .{ "URBA", .Urban },
    .{ "INDO", .Indoor },
    .{ "WATR", .Water },
    .{ "VEGE", .Vegetation },
    .{ "BEAC", .Beach },
});

fn resolveLocation(fcc: gpmf.FourCC) ?Location {
    return locMap.get(&fcc);
}

/// Probability that the scene is of a certain type.
pub const SceneScore = struct {
    Urban: f32,
    Indoor: f32,
    Water: f32,
    Vegetation: f32,
    Beach: f32,
    Snow: f32,
};

pub const Hue = struct {
    hue: u8,
    weight: u8,

    pub fn hsv(self: Hue) f32 {
        return @as(f32, @floatFromInt(self.hue)) * 360.0 / 255.0;
    }
};

/// A telemetry value.
/// Some values contain multiple readings.
pub const TVal = union(enum) {
    Accl: TempXYX,
    Gyro: TempXYX,
    Faces: []Face,
    /// Older-style GPS readings
    GPS5: []GPSReading,
    /// Newer style GPS readings (better frequency and precision)
    GPS9: []GPSReading,
    AudioLevel: AudioLevel,
    Scene: SceneScore,
    Luminance: f32,
    Hues: []Hue,
    Uniformity: f32,
    WhiteBalance: u16,
    Shutter: f32,
};

/// A named collection of telemetry data.
/// The telemetry values should generally be considered uniform within this collection.
pub const Telemetry = struct {
    stmp: u64,
    tsmp: u64,
    name: []const u8,
    units: [][]const u8,
    siunits: [][]const u8,
    values: []TVal,
};

fn telemCmp(_: void, a: Telemetry, b: Telemetry) bool {
    if (a.tsmp == b.tsmp) {
        return std.mem.order(u8, a.name, b.name) == .lt;
    }
    return (a.tsmp < b.tsmp);
}

/// High level representation of device telemetry.
pub const DEVC = struct {
    id: u32,
    name: []const u8,
    telems: []Telemetry,
    arena: *std.heap.ArenaAllocator,
    /// Bits of the telemetry stream that were not handled (along with their cardinality).
    ignored: std.AutoHashMap(gpmf.FourCC, u32),
    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        // self.ignored.deinit();
        allocator.destroy(self.arena);
    }
};

/// Build a DEVC from a parsed stream of GPMF data.
/// The GPMF data should've been parsed by gpmf.parse()
pub fn mkDEVC(oalloc: std.mem.Allocator, data: gpmf.Parsed) anyerror!DEVC {
    if (data.value != .nested) {
        return error.Invalid;
    }
    const fcc = data.value.nested.fourcc;
    if (!gpmf.eqFourCC(fcc, constants.DEVC)) {
        std.debug.print("unexpecdted fourcc making a DEVC: {s}\n", .{fcc});
        return error.Invalid;
    }
    var arena = try oalloc.create(std.heap.ArenaAllocator);
    errdefer oalloc.destroy(arena);
    arena.* = std.heap.ArenaAllocator.init(oalloc);
    errdefer arena.deinit();
    const alloc = arena.allocator();
    const hm = std.AutoHashMap(gpmf.FourCC, u32).init(alloc);

    var devc = DEVC{
        .id = 0,
        .name = "",
        .telems = &.{},
        .arena = arena,
        .ignored = hm,
    };
    var telems = std.ArrayList(Telemetry).init(alloc);
    for (data.value.nested.data) |v| {
        switch (v) {
            .nested => {
                const nested = v.nested;
                if (gpmf.eqFourCC(nested.fourcc, constants.DVID)) {
                    devc.id = try nested.data[0].as(u32);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.DVNM)) {
                    devc.name = try nested.data[0].as([]const u8);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.STRM)) {
                    try recordTelemetry(alloc, &devc, &telems, nested.data);
                }
            },
            else => {},
        }
    }
    devc.telems = try telems.toOwnedSlice();
    std.mem.sort(Telemetry, devc.telems, {}, telemCmp);

    return devc;
}

const ParserState = struct {
    gpsu: zeit.Instant,
    gpsf: u32,
    gpsp: f64,
    scal: []gpmf.Value,
    tmpc: f64,
};

fn parseAudioLevel(alloc: std.mem.Allocator, _: *ParserState, data: []gpmf.Value) !TVal {
    var al = AudioLevel{
        .rms = try alloc.alloc(f32, data.len / 2),
        .peak = try alloc.alloc(f32, data.len / 2),
    };
    for (0..data.len / 2, 0..) |i, o| {
        const b = i * 2;
        al.rms[o] = try data[b].as(f32);
        al.peak[o] = try data[b + 1].as(f32);
    }
    return TVal{ .AudioLevel = al };
}

fn parseScene(_: std.mem.Allocator, _: *ParserState, data: []gpmf.Value) !TVal {
    var scn = TVal{ .Scene = .{ .Beach = 0, .Urban = 0, .Indoor = 0, .Water = 0, .Vegetation = 0, .Snow = 0 } };
    for (data) |nd| {
        const want: []const u8 = "Ff";
        if (nd != .complex) {
            std.debug.print("   not complex: {any}\n", .{nd});
            continue;
        }
        if (!std.mem.eql(u8, nd.complex.fmt, want)) {
            std.debug.print("   incorrect format: {u} ({any}) want {u} ({any})\n", .{ nd.complex.fmt, nd.complex.fmt, want, want });
            continue;
        }
        const fcc = nd.complex.data[0].F;
        const score = try nd.complex.data[1].as(f32);
        switch (resolveLocation(fcc) orelse unreachable) {
            .Urban => scn.Scene.Urban = score,
            .Indoor => scn.Scene.Indoor = score,
            .Water => scn.Scene.Water = score,
            .Vegetation => scn.Scene.Vegetation = score,
            .Beach => scn.Scene.Beach = score,
            .Snow => scn.Scene.Snow = score,
        }
    }
    return scn;
}

fn parseFaces(alloc: std.mem.Allocator, _: *ParserState, data: []gpmf.Value) !?TVal {
    var faces = std.ArrayList(Face).init(alloc);
    for (data) |nd| {
        if (nd != .complex) {
            std.debug.print("   not complex: {any}\n", .{nd});
            continue;
        }
        if (std.mem.eql(u8, nd.complex.fmt, "Lffffff")) {
            try faces.append(Face{
                .id = try nd.complex.data[0].as(i32),
                .x = try nd.complex.data[1].as(f32),
                .y = try nd.complex.data[2].as(f32),
                .w = try nd.complex.data[3].as(f32),
                .h = try nd.complex.data[4].as(f32),
                .smile = try nd.complex.data[6].as(f32),
            });
        } else if (std.mem.eql(u8, nd.complex.fmt, "Lffff")) {
            try faces.append(Face{
                .id = try nd.complex.data[0].as(i32),
                .x = try nd.complex.data[1].as(f32),
                .y = try nd.complex.data[2].as(f32),
                .w = try nd.complex.data[3].as(f32),
                .h = try nd.complex.data[4].as(f32),
                .smile = 0,
            });
        } else {
            std.debug.print("   incorrect face format: {any}\n", .{nd.complex.fmt});
            continue;
        }
    }
    if (faces.items.len == 0) {
        return null;
    }
    return TVal{ .Faces = try faces.toOwnedSlice() };
}

fn parseGPS5(alloc: std.mem.Allocator, state: *ParserState, data: []gpmf.Value) !TVal {
    var gpses = try alloc.alloc(GPSReading, data.len / 5);
    for (0..data.len / 5, 0..) |i, o| {
        const b = i * 5;
        gpses[o] = .{
            .lat = try data[b].as(f64) / try state.scal[0].as(f64),
            .lon = try data[b + 1].as(f64) / try state.scal[1].as(f64),
            .alt = try data[b + 2].as(f64) / try state.scal[2].as(f64),
            .speed2d = try data[b + 3].as(f64) / try state.scal[3].as(f64),
            .speed3d = try data[b + 4].as(f64) / try state.scal[4].as(f64),
            .time = state.gpsu,
            .dop = state.gpsp,
            .fix = state.gpsf,
        };
    }
    return TVal{ .GPS5 = gpses };
}

fn parseGPS9(alloc: std.mem.Allocator, state: *ParserState, data: []gpmf.Value) !?TVal {
    if (state.scal.len < 8) {
        std.debug.print("   scal too short (need at least 8): {any}\n", .{state.scal});
        return null;
    }
    const baseTime = try zeit.instant(.{
        .source = .{ .iso8601 = "2000-01-01T00:00:00Z" },
    });

    const lats = try state.scal[0].as(f64);
    const lons = try state.scal[1].as(f64);
    const alts = try state.scal[2].as(f64);
    const s2ds = try state.scal[3].as(f64);
    const s3ds = try state.scal[4].as(f64);
    const dops = try state.scal[7].as(f64);

    var gpses = try alloc.alloc(GPSReading, data.len);

    for (data, 0..) |gv, o| {
        const want: []const u8 = "lllllllSS";
        if (gv != .complex) {
            std.debug.print("   not complex: {any}\n", .{gv});
            continue;
        }
        if (!std.mem.eql(u8, gv.complex.fmt, want)) {
            std.debug.print("   incorrect format: {u} ({any}) want {u} ({any})\n", .{ gv.complex.fmt, gv.complex.fmt, want, want });
            continue;
        }
        const gd = gv.complex.data;
        const dur = zeit.Duration{
            .days = try gd[5].as(usize),
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
            .milliseconds = try gd[6].as(usize),
            .microseconds = 0,
            .nanoseconds = 0,
        };

        gpses[o] = .{
            .lat = try gd[0].as(f64) / lats,
            .lon = try gd[1].as(f64) / lons,
            .alt = try gd[2].as(f64) / alts,
            .speed2d = try gd[3].as(f64) / s2ds,
            .speed3d = try gd[4].as(f64) / s3ds,
            .time = try baseTime.add(dur),
            .dop = try gd[7].as(f64) / dops,
            .fix = try gd[8].as(u32),
        };
    }

    return TVal{ .GPS9 = gpses };
}

fn recordTelemetry(alloc: std.mem.Allocator, devc: *DEVC, telems: *std.ArrayList(Telemetry), data: []gpmf.Value) !void {
    var telem = Telemetry{ .stmp = 0, .tsmp = 0, .name = "", .values = &.{}, .units = &.{}, .siunits = &.{} };
    var vala = std.ArrayList(TVal).init(alloc);
    var state = ParserState{
        .gpsu = try zeit.instant(.{}),
        .gpsf = 0,
        .gpsp = 0,
        .scal = &.{},
        .tmpc = 0,
    };

    for (data) |v| {
        switch (v) {
            .nested => {
                const nested = v.nested;
                if (gpmf.eqFourCC(nested.fourcc, constants.STNM)) {
                    telem.name = try nested.data[0].as([]const u8);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.TSMP)) {
                    telem.tsmp = try nested.data[0].as(u64);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.AALP)) {
                    try vala.append(try parseAudioLevel(alloc, &state, nested.data));
                } else if (gpmf.eqFourCC(nested.fourcc, constants.SCEN)) {
                    try vala.append(try parseScene(alloc, &state, nested.data));
                } else if (gpmf.eqFourCC(nested.fourcc, constants.FACE)) {
                    if (try parseFaces(alloc, &state, nested.data)) |f| {
                        try vala.append(f);
                    }
                } else if (gpmf.eqFourCC(nested.fourcc, constants.SCAL)) {
                    state.scal = nested.data;
                } else if (gpmf.eqFourCC(nested.fourcc, constants.TMPC)) {
                    state.tmpc = try nested.data[0].as(f64);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.GPSU)) {
                    if (nested.data[0] == .U) {
                        state.gpsu = nested.data[0].U;
                    }
                } else if (gpmf.eqFourCC(nested.fourcc, constants.GPSF)) {
                    state.gpsf = try nested.data[0].as(u32);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.GPSP)) {
                    state.gpsp = try nested.data[0].as(f64);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.GPS5)) {
                    try vala.append(try parseGPS5(alloc, &state, nested.data));
                } else if (gpmf.eqFourCC(nested.fourcc, constants.GPS9)) {
                    if (try parseGPS9(alloc, &state, nested.data)) |gps| {
                        try vala.append(gps);
                    }
                } else if (gpmf.eqFourCC(nested.fourcc, constants.GPS9)) {
                    std.debug.print(" GPS9: scal={any}\n    {any}\n", .{ state.scal, nested.data });
                } else if (gpmf.eqFourCC(nested.fourcc, constants.GYRO)) {
                    try vala.append(TVal{ .Gyro = try parseAG(alloc, &state, nested.data) });
                } else if (gpmf.eqFourCC(nested.fourcc, constants.ACCL)) {
                    try vala.append(TVal{ .Accl = try parseAG(alloc, &state, nested.data) });
                } else if (gpmf.eqFourCC(nested.fourcc, constants.UNIT)) {
                    try parseUnits(alloc, &state, nested.data, &telem.units);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.SIUN)) {
                    try parseUnits(alloc, &state, nested.data, &telem.siunits);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.STMP)) {
                    telem.stmp = try nested.data[0].as(u64);
                } else if (gpmf.eqFourCC(nested.fourcc, constants.YAVG)) {
                    try vala.append(TVal{ .Luminance = try avg(f32, nested.data) });
                } else if (gpmf.eqFourCC(nested.fourcc, constants.HUES)) {
                    try vala.append(try parseHues(alloc, &state, nested.data));
                } else if (gpmf.eqFourCC(nested.fourcc, constants.UNIF)) {
                    try vala.append(TVal{ .Uniformity = try avg(f32, nested.data) });
                } else if (gpmf.eqFourCC(nested.fourcc, constants.WBAL)) {
                    try vala.append(TVal{ .WhiteBalance = try avg(u16, nested.data) });
                } else if (gpmf.eqFourCC(nested.fourcc, constants.SHUT)) {
                    try vala.append(TVal{ .Shutter = try avg(f32, nested.data) });
                } else {
                    const entry = try devc.ignored.getOrPut(nested.fourcc);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = 0;
                    }
                    entry.value_ptr.* += 1;
                }
            },
            else => {},
        }
    }

    telem.values = try vala.toOwnedSlice();
    try telems.append(telem);
}
fn avg(comptime T: type, data: []gpmf.Value) !T {
    if (data.len == 0) {
        return 0;
    }
    var sum: T = 0;
    for (data) |d| {
        sum += try d.as(T);
    }
    switch (@typeInfo(T)) {
        .Int => return sum / @as(T, @intCast(data.len)),
        .Float => return sum / @as(T, @floatFromInt(data.len)),
        else => return error.Invalid,
    }
}

fn parseHues(alloc: std.mem.Allocator, _: *ParserState, data: []gpmf.Value) !TVal {
    var hues = try alloc.alloc(Hue, data.len);
    errdefer alloc.free(hues);
    for (data, 0..) |d, o| {
        if (d != .complex) {
            return error.Invalid;
        }
        const cd = d.complex;
        if (!std.mem.eql(u8, cd.fmt, "BB")) {
            return error.Invalid;
        }
        hues[o] = .{
            .hue = try cd.data[0].as(u8),
            .weight = try cd.data[1].as(u8),
        };
    }
    return TVal{ .Hues = hues };
}

fn fixUnits(alloc: std.mem.Allocator, data: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(alloc);
    for (data) |c| {
        if (c == 0) {
            break;
        }
        if (c == 0xB0) { // This is an old-style degree symbol we'll convert to utf8.
            try buf.append(0xc2);
            try buf.append(0xb2);
            continue;
        }
        try buf.append(c);
    }
    return buf.toOwnedSlice();
}

test fixUnits {
    const got = try fixUnits(std.testing.allocator, "abc");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("abc", got);
    const got2 = try fixUnits(std.testing.allocator, "abc\xb0");
    defer std.testing.allocator.free(got2);
    try std.testing.expectEqualStrings("abc\xc2\xb2", got2);
}

fn parseUnits(alloc: std.mem.Allocator, _: *ParserState, data: []gpmf.Value, into: *[][]const u8) !void {
    if (into.len > 0) {
        alloc.free(into.*);
    }
    into.* = try alloc.alloc([]const u8, data.len);
    for (0..data.len, 0..) |i, o| {
        into.*[o] = try fixUnits(alloc, try data[i].as([]const u8));
    }
}

test parseUnits {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var data = [_]gpmf.Value{
        .{ .c = "m/s" },
        .{ .c = "m\x00\x00" },
        .{ .c = "m\xb0" },
    };
    var units = try arena.allocator().alloc([]const u8, 3);

    try parseUnits(arena.allocator(), undefined, &data, &units);
    try std.testing.expectEqual(units.len, 3);
    try std.testing.expectEqualStrings("m/s", units[0]);
    try std.testing.expectEqualStrings("m", units[1]);
    try std.testing.expectEqualStrings("m²", units[2]);
}

fn parseAG(alloc: std.mem.Allocator, state: *ParserState, data: []gpmf.Value) !TempXYX {
    var vals = try alloc.alloc(XYZ, data.len / 3);
    const sc = try state.scal[0].as(f32);
    for (0..data.len / 3, 0..) |i, o| {
        const b = i * 3;
        vals[o] = .{
            .x = try data[b].as(f32) / sc,
            .y = try data[b + 1].as(f32) / sc,
            .z = try data[b + 2].as(f32) / sc,
        };
    }

    return .{ .temp = @floatCast(state.tmpc), .vals = vals };
}

test parseAG {
    var allocator = std.testing.allocator;
    var scaling: [1]gpmf.Value = .{.{ .f = 1.0 }};
    var state = ParserState{
        .gpsu = try zeit.instant(.{}),
        .gpsf = 0,
        .gpsp = 0.0,
        .scal = scaling[0..],
        .tmpc = 20.0, // example temperature value
    };

    // Prepare data for one XYZ triplet.
    var values = try allocator.alloc(gpmf.Value, 6);
    defer allocator.free(values);
    for (values, 1..) |_, i| {
        values[i - 1] = .{ .f = @floatFromInt(i) };
    }

    const result = try parseAG(allocator, &state, values[0..]);
    defer allocator.free(result.vals);

    try std.testing.expectEqual(result.temp, 20.0);
    var e: f32 = 1;
    for (result.vals) |v| {
        inline for (@typeInfo((XYZ)).Struct.fields) |field| {
            try std.testing.expectEqual(e, @field(v, field.name));
            e = e + 1;
        }
    }
}
