const std = @import("std");
const gpmf = @import("gpmf.zig");
const devc = @import("devc.zig");

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
        const d = try devc.mkDEVC(allocator, parsed);
        defer d.deinit();
        std.debug.print("DEVC: id={d}, name: {s}\n", .{ d.id, d.name });
        for (d.telems) |t| {
            std.debug.print("  Telemetry: stmp={d}, tsmp={d}, name: {s}\n", .{ t.stmp, t.tsmp, t.name });
            for (t.values) |v| {
                switch (v) {
                    .AudioLevel => {
                        const al = v.AudioLevel;
                        std.debug.print("    AudioLevel: rms={d}, peak={d}\n", .{ al.rms, al.peak });
                    },
                    .Scene => {
                        std.debug.print("    Scene:\n", .{});
                        inline for (@typeInfo((devc.SceneScore)).Struct.fields) |field| {
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

fn showGPS(v: u8, gps: devc.GPSReading) !void {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();
    try gps.time.time().strftime(w, "%Y-%m-%d %H:%M:%S:%f %Z");

    std.debug.print("    GPS{d}@{s}\n", .{ v, fbs.getWritten() });
    inline for (@typeInfo((devc.GPSReading)).Struct.fields) |field| {
        if (comptime std.mem.eql(u8, "time", field.name)) continue;
        std.debug.print("      - {s}: {d}\n", .{ field.name, @field(gps, field.name) });
    }
}
