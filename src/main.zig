const std = @import("std");
const gpmf = @import("gpmf.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const args = std.process.argsAlloc(allocator) catch return;
    defer std.process.argsFree(allocator, args);

    var f = try std.fs.openFileAbsolute(args[1], std.fs.File.OpenFlags{});
    defer f.close();

    while (true) {
        const nested = gpmf.parse(arena.allocator(), f.reader().any()) catch |err| switch (err) {
            error.EndOfStream => return void{},
            else => unreachable,
        };
        try std.json.stringifyMaxDepth(nested, .{}, std.io.getStdOut().writer(), null);
        try std.io.getStdOut().writer().writeByte('\n');
    }
}
