const std = @import("std");
const gpmf = @import("gpmf");
const tstream = gpmf.tstream;

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

    while (true) {
        const parsed = gpmf.parse(allocator, infile.reader().any()) catch |err| switch (err) {
            error.EndOfStream => return void{},
            else => {
                std.debug.print("Error parsing: {any}", .{err});
                unreachable;
            },
        };
        defer parsed.deinit();
        const d = try tstream.mkTelemetryStream(allocator, parsed);
        defer d.deinit();
        std.debug.print("TelemetryStream: id={d}, name: {s}\n", .{ d.id, d.name });
        for (d.telems) |t| {
            if (t.values.len == 0) continue;
            std.debug.print("  Telemetry: stmp={d}, tsmp={d}, name: {s}\n", .{ t.stmp, t.tsmp, t.name });
            printUnits("Units", t.units);
            printUnits("SI Units", t.siunits);
            for (t.values) |v| {
                switch (v) {
                    .Shutter => {
                        std.debug.print("    Shutter: {d}\n", .{v.Shutter});
                    },
                    .ISO => {
                        std.debug.print("    ISO: {d}\n", .{v.ISO});
                    },
                    .AudioLevel => {
                        const al = v.AudioLevel;
                        std.debug.print("    AudioLevel: rms={d}, peak={d}\n", .{ al.rms, al.peak });
                    },
                    .Luminance => {
                        std.debug.print("    Luminance: {d}\n", .{v.Luminance});
                    },
                    .Hues => {
                        for (v.Hues) |h| {
                            std.debug.print("    Hue: {d}, HSV: {d}, level: {d}\n", .{ h.hue, h.hsv(), h.weight });
                        }
                    },
                    .WhiteBalance => {
                        std.debug.print("    {d}K\n", .{v.WhiteBalance});
                    },
                    .WRGB => {
                        for (v.WRGB) |w| {
                            std.debug.print("    r={d} g={d} b={d}\n", .{ w.r, w.g, w.b });
                        }
                    },

                    .Uniformity => {
                        std.debug.print("    Uniformity: {d}\n", .{v.Uniformity});
                    },
                    .Scene => {
                        std.debug.print("    Scene:\n", .{});
                        inline for (@typeInfo((tstream.SceneScore)).Struct.fields) |field| {
                            std.debug.print("      - {s}: {d}\n", .{ field.name, @field(v.Scene, field.name) });
                        }
                    },
                    .Faces => {
                        for (v.Faces) |f| {
                            std.debug.print("    Face: ({d},{d}) ({d},{d}) smile={d}\n", .{ f.x, f.y, f.w, f.h, f.smile });
                        }
                    },
                    .Gyro => {
                        std.debug.print("    Gyro (temp={d}):\n", .{v.Gyro.temp});
                        for (v.Gyro.vals) |xyz| {
                            std.debug.print("      - {d} {d} {d}\n", .{ xyz.x, xyz.y, xyz.z });
                        }
                    },
                    .Accl => {
                        std.debug.print("    Accelerometer (temp={d}):\n", .{v.Accl.temp});
                        for (v.Accl.vals) |xyz| {
                            std.debug.print("      - {d} {d} {d}\n", .{ xyz.x, xyz.y, xyz.z });
                        }
                    },
                    .GPS5 => {
                        for (v.GPS5) |gps| {
                            try showGPS(5, gps);
                        }
                    },
                    .GPS9 => {
                        for (v.GPS9) |gps| {
                            try showGPS(9, gps);
                        }
                    },
                    .CameraOrientation => {
                        for (v.CameraOrientation) |o| {
                            std.debug.print("    Camera orientation quaternion: (w={d}, x={d}, y={d}, z={d})\n", .{ o.w, o.x, o.y, o.z });
                        }
                    },
                    .ImageOrientation => {
                        for (v.ImageOrientation) |o| {
                            std.debug.print("    Image orientation quaternion: (w={d}, x={d}, y={d}, z={d})\n", .{ o.w, o.x, o.y, o.z });
                        }
                    },
                    .Gravity => {
                        for (v.Gravity) |g| {
                            std.debug.print("    x={d} y={d} z={d}\n", .{ g.x, g.y, g.z });
                        }
                    },
                    .MicWet => {
                        std.debug.print("    Mic wetness: {d}\n", .{v.MicWet});
                    },
                    .WindProcessing => {
                        std.debug.print("    Wind processing: {d}\n", .{v.WindProcessing});
                    },
                }
            }
        }
        try std.io.getStdOut().writer().writeByte('\n');
        var iterator = d.ignored.iterator();
        std.debug.print("Ignored:\n", .{});
        while (iterator.next()) |entry| {
            std.debug.print("  {s} {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
}

fn printUnits(name: []const u8, units: [][]const u8) void {
    if (units.len == 0) return;
    std.debug.print("    {s}: ", .{name});
    for (units, 0..units.len) |u, i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        for (u) |c| {
            std.debug.print("{u}", .{c});
        }
    }
    std.debug.print("\n", .{});
}

fn showGPS(v: u8, gps: tstream.GPSReading) !void {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();
    try gps.time.time().strftime(w, "%Y-%m-%d %H:%M:%S:%f %Z");

    std.debug.print("    GPS{d}@{s} altref={s}\n", .{ v, fbs.getWritten(), gps.altRef });
    inline for (@typeInfo((tstream.GPSReading)).Struct.fields) |field| {
        if (comptime std.mem.eql(u8, "time", field.name)) continue;
        if (comptime std.mem.eql(u8, "altRef", field.name)) continue;
        std.debug.print("      - {s}: {d}\n", .{ field.name, @field(gps, field.name) });
    }
}
