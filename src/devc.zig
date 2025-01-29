const std = @import("std");
const gpmf = @import("gpmf.zig");
const zeit = @import("zeit");

pub const XYZ = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Accelerometer = struct {
    temp: f32,
    vals: []XYZ,
};

pub const Gyroscope = struct {
    temp: f32,
    vals: []XYZ,
};

pub const Face = struct {
    id: i32,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    smile: f32,
};

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

pub const AudioLevel = struct {
    rms: []f32,
    peak: []f32,
};

pub const Location = enum {
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

pub const SceneScore = struct {
    Urban: f32,
    Indoor: f32,
    Water: f32,
    Vegetation: f32,
    Beach: f32,
};

pub const TVal = union(enum) {
    Unknown: []gpmf.Value,
    Accl: Accelerometer,
    Gyro: Gyroscope,
    Faces: []Face,
    GPS5: []GPSReading,
    GPS9: []GPSReading,
    AudioLevel: AudioLevel,
    Scene: SceneScore,
};

pub const Telemetry = struct {
    stmp: u64,
    tsmp: u64,
    name: []const u8,
    values: []TVal,
};

fn telemCmp(_: void, a: Telemetry, b: Telemetry) bool {
    if (a.tsmp == b.tsmp) {
        return std.mem.order(u8, a.name, b.name) == .lt;
    }
    return (a.tsmp < b.tsmp);
}

pub const DEVC = struct {
    id: u32,
    name: []const u8,
    telems: []Telemetry,
    arena: *std.heap.ArenaAllocator,
    ignored: std.AutoHashMap(gpmf.FourCC, u32),
    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        // self.ignored.deinit();
        allocator.destroy(self.arena);
    }
};

pub fn mkDEVC(oalloc: std.mem.Allocator, fcc: gpmf.FourCC, data: []gpmf.Value) anyerror!DEVC {
    if (!gpmf.eqFourCC(fcc, gpmf.DEVC)) {
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
    for (data) |v| {
        switch (v) {
            .nested => {
                const nested = v.nested;
                if (gpmf.eqFourCC(nested.fourcc, gpmf.DVID)) {
                    devc.id = try gpmf.extractValue(u32, nested.data[0]);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.DVNM)) {
                    devc.name = try gpmf.extractValue([]const u8, nested.data[0]);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.STRM)) {
                    try recordTelemetry(alloc, &devc, &telems, nested.data);
                }
            },
            else => {},
        }
    }
    devc.telems = try telems.toOwnedSlice();
    // std.mem.sort(u8, &data, {}, comptime std.sort.asc(u8));
    std.mem.sort(Telemetry, devc.telems, {}, telemCmp);

    return devc;
}

fn recordTelemetry(alloc: std.mem.Allocator, devc: *DEVC, telems: *std.ArrayList(Telemetry), data: []gpmf.Value) !void {
    var telem = Telemetry{ .stmp = 0, .tsmp = 0, .name = "", .values = &.{} };
    var vala = std.ArrayList(TVal).init(alloc);
    var gpsu: zeit.Instant = try zeit.instant(.{});
    var gpsf: u32 = 0;
    var gpsp: f64 = 0;
    var scal: []gpmf.Value = &.{};
    var tmpc: f64 = 0;
    for (data) |v| {
        switch (v) {
            .nested => {
                const nested = v.nested;
                if (gpmf.eqFourCC(nested.fourcc, gpmf.STNM)) {
                    telem.name = try gpmf.extractValue([]const u8, nested.data[0]);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.TSMP)) {
                    telem.tsmp = try gpmf.extractValue(u64, nested.data[0]);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.AALP)) {
                    var al = AudioLevel{
                        .rms = try alloc.alloc(f32, nested.data.len / 2),
                        .peak = try alloc.alloc(f32, nested.data.len / 2),
                    };
                    for (0..nested.data.len / 2, 0..) |i, o| {
                        const b = i * 2;
                        al.rms[o] = try gpmf.extractValue(f32, nested.data[b]);
                        al.peak[o] = try gpmf.extractValue(f32, nested.data[b + 1]);
                    }
                    try vala.append(TVal{ .AudioLevel = al });
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.SCEN)) {
                    var scn = TVal{ .Scene = .{ .Beach = 0, .Urban = 0, .Indoor = 0, .Water = 0, .Vegetation = 0 } };
                    for (nested.data) |nd| {
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
                        const score = try gpmf.extractValue(f32, nd.complex.data[1]);
                        switch (resolveLocation(fcc) orelse unreachable) {
                            .Urban => scn.Scene.Urban = score,
                            .Indoor => scn.Scene.Indoor = score,
                            .Water => scn.Scene.Water = score,
                            .Vegetation => scn.Scene.Vegetation = score,
                            .Beach => scn.Scene.Beach = score,
                            else => {},
                        }
                    }
                    try vala.append(scn);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.FACE)) {
                    var faces = std.ArrayList(Face).init(alloc);
                    for (nested.data) |nd| {
                        if (nd != .complex) {
                            std.debug.print("   not complex: {any}\n", .{nd});
                            continue;
                        }
                        if (std.mem.eql(u8, nd.complex.fmt, "Lffffff")) {
                            try faces.append(Face{
                                .id = try gpmf.extractValue(i32, nd.complex.data[0]),
                                .x = try gpmf.extractValue(f32, nd.complex.data[1]),
                                .y = try gpmf.extractValue(f32, nd.complex.data[2]),
                                .w = try gpmf.extractValue(f32, nd.complex.data[3]),
                                .h = try gpmf.extractValue(f32, nd.complex.data[4]),
                                .smile = try gpmf.extractValue(f32, nd.complex.data[6]),
                            });
                        } else if (std.mem.eql(u8, nd.complex.fmt, "Lffff")) {
                            try faces.append(Face{
                                .id = try gpmf.extractValue(i32, nd.complex.data[0]),
                                .x = try gpmf.extractValue(f32, nd.complex.data[1]),
                                .y = try gpmf.extractValue(f32, nd.complex.data[2]),
                                .w = try gpmf.extractValue(f32, nd.complex.data[3]),
                                .h = try gpmf.extractValue(f32, nd.complex.data[4]),
                                .smile = 0,
                            });
                        } else {
                            std.debug.print("   incorrect face format: {any}\n", .{nd.complex.fmt});
                            continue;
                        }
                    }
                    if (faces.items.len > 0) {
                        try vala.append(TVal{ .Faces = try faces.toOwnedSlice() });
                    }
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.SCAL)) {
                    scal = nested.data;
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.TMPC)) {
                    tmpc = try gpmf.extractValue(f64, nested.data[0]);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.GPSU)) {
                    if (nested.data[0] == .U) {
                        gpsu = nested.data[0].U;
                    }
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.GPSF)) {
                    gpsf = try gpmf.extractValue(u32, nested.data[0]);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.GPSP)) {
                    gpsp = try gpmf.extractValue(f64, nested.data[0]);
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.GPS5)) {
                    var gpses = try alloc.alloc(GPSReading, nested.data.len / 5);
                    for (0..nested.data.len / 5, 0..) |i, o| {
                        const b = i * 5;
                        gpses[o] = .{
                            .lat = try gpmf.extractValue(f64, nested.data[b]) / try gpmf.extractValue(f64, scal[0]),
                            .lon = try gpmf.extractValue(f64, nested.data[b + 1]) / try gpmf.extractValue(f64, scal[1]),
                            .alt = try gpmf.extractValue(f64, nested.data[b + 2]) / try gpmf.extractValue(f64, scal[2]),
                            .speed2d = try gpmf.extractValue(f64, nested.data[b + 3]) / try gpmf.extractValue(f64, scal[3]),
                            .speed3d = try gpmf.extractValue(f64, nested.data[b + 4]) / try gpmf.extractValue(f64, scal[4]),
                            .time = gpsu,
                            .dop = gpsp,
                            .fix = gpsf,
                        };
                    }
                    try vala.append(TVal{ .GPS5 = gpses });
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.GPS9)) {
                    if (scal.len < 8) {
                        std.debug.print("   scal too short (need at least 8): {any}\n", .{scal});
                        continue;
                    }
                    const baseTime = try zeit.instant(.{
                        .source = .{ .iso8601 = "2000-01-01T00:00:00Z" },
                    });

                    const lats = try gpmf.extractValue(f64, scal[0]);
                    const lons = try gpmf.extractValue(f64, scal[1]);
                    const alts = try gpmf.extractValue(f64, scal[2]);
                    const s2ds = try gpmf.extractValue(f64, scal[3]);
                    const s3ds = try gpmf.extractValue(f64, scal[4]);
                    const dops = try gpmf.extractValue(f64, scal[7]);
                    var gpses = try alloc.alloc(GPSReading, nested.data.len);
                    for (nested.data, 0..) |gv, o| {
                        const want: []const u8 = "lllllllSS";
                        if (gv != .complex) {
                            std.debug.print("   not complex: {any}\n", .{gv});
                            continue;
                        }
                        if (!std.mem.eql(u8, gv.complex.fmt, want)) {
                            std.debug.print("   incorrect format: {u} ({any}) want {u} ({any})\n", .{ gv.complex.fmt, gv.complex.fmt, want, want });
                            continue;
                        }
                        const dur = zeit.Duration{
                            .days = try gpmf.extractValue(usize, gv.complex.data[5]),
                            .hours = 0,
                            .minutes = 0,
                            .seconds = 0,
                            .milliseconds = try gpmf.extractValue(usize, gv.complex.data[6]),
                            .microseconds = 0,
                            .nanoseconds = 0,
                        };

                        const gd = gv.complex.data;
                        gpses[o] = .{
                            .lat = try gpmf.extractValue(f64, gd[0]) / lats,
                            .lon = try gpmf.extractValue(f64, gd[1]) / lons,
                            .alt = try gpmf.extractValue(f64, gd[2]) / alts,
                            .speed2d = try gpmf.extractValue(f64, gd[3]) / s2ds,
                            .speed3d = try gpmf.extractValue(f64, gd[4]) / s3ds,
                            .time = try baseTime.add(dur),
                            .dop = try gpmf.extractValue(f64, gd[7]) / dops,
                            .fix = try gpmf.extractValue(u32, gd[8]),
                        };
                    }
                    try vala.append(TVal{ .GPS9 = gpses });
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.GPS9)) {
                    std.debug.print(" GPS9: scal={any}\n    {any}\n", .{ scal, nested.data });
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.GYRO)) {
                    var vals = try alloc.alloc(XYZ, nested.data.len / 3);
                    for (0..nested.data.len / 3, 0..) |i, o| {
                        const b = i * 3;
                        vals[o] = .{
                            .x = try gpmf.extractValue(f32, nested.data[b]) / try gpmf.extractValue(f32, scal[0]),
                            .y = try gpmf.extractValue(f32, nested.data[b + 1]) / try gpmf.extractValue(f32, scal[0]),
                            .z = try gpmf.extractValue(f32, nested.data[b + 2]) / try gpmf.extractValue(f32, scal[0]),
                        };
                    }
                    try vala.append(TVal{ .Gyro = .{ .temp = @floatCast(tmpc), .vals = vals } });
                } else if (gpmf.eqFourCC(nested.fourcc, gpmf.ACCL)) {
                    // TODO: This is pretty much a duplicate of above.
                    var vals = try alloc.alloc(XYZ, nested.data.len / 3);
                    for (0..nested.data.len / 3, 0..) |i, o| {
                        const b = i * 3;
                        vals[o] = .{
                            .x = try gpmf.extractValue(f32, nested.data[b]) / try gpmf.extractValue(f32, scal[0]),
                            .y = try gpmf.extractValue(f32, nested.data[b + 1]) / try gpmf.extractValue(f32, scal[0]),
                            .z = try gpmf.extractValue(f32, nested.data[b + 2]) / try gpmf.extractValue(f32, scal[0]),
                        };
                    }
                    try vala.append(TVal{ .Accl = .{ .temp = @floatCast(tmpc), .vals = vals } });
                } else {
                    const entry = try devc.ignored.getOrPut(nested.fourcc);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = 0;
                    }
                    entry.value_ptr.* += 1;
                    // std.debug.print(" unhandled telem fourcc: {s}\n", .{nested.fourcc});
                }
            },
            else => {},
        }
    }
    telem.values = try vala.toOwnedSlice();
    try telems.append(telem);
}
