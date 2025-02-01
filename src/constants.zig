/// A collection of FourCC constants used throughout this library.
const std = @import("std");
const gpmf = @import("gpmf.zig");
const testing = std.testing;

pub const DEVC: gpmf.FourCC = fourcc("DEVC");
pub const DVID: gpmf.FourCC = fourcc("DVID");
pub const DVNM: gpmf.FourCC = fourcc("DVNM");
pub const STRM: gpmf.FourCC = fourcc("STRM");
pub const STMP: gpmf.FourCC = fourcc("STMP");
pub const TSMP: gpmf.FourCC = fourcc("TSMP");
pub const STNM: gpmf.FourCC = fourcc("STNM");
pub const AALP: gpmf.FourCC = fourcc("AALP");
pub const ACCL: gpmf.FourCC = fourcc("ACCL");
pub const SCEN: gpmf.FourCC = fourcc("SCEN");
pub const SNOW: gpmf.FourCC = fourcc("SNOW");
pub const URBA: gpmf.FourCC = fourcc("URBA");
pub const INDO: gpmf.FourCC = fourcc("INDO");
pub const WATR: gpmf.FourCC = fourcc("WATR");
pub const VEGE: gpmf.FourCC = fourcc("VEGE");
pub const BEAC: gpmf.FourCC = fourcc("BEAC");
pub const URBN: gpmf.FourCC = fourcc("URBN");
pub const INDR: gpmf.FourCC = fourcc("INDR");
pub const FACE: gpmf.FourCC = fourcc("FACE");
pub const GPSF: gpmf.FourCC = fourcc("GPSF");
pub const GPSU: gpmf.FourCC = fourcc("GPSU");
pub const GPSP: gpmf.FourCC = fourcc("GPSP");
pub const GPS5: gpmf.FourCC = fourcc("GPS5");
pub const GPS9: gpmf.FourCC = fourcc("GPS9");
pub const SCAL: gpmf.FourCC = fourcc("SCAL");
pub const TMPC: gpmf.FourCC = fourcc("TMPC");
pub const GYRO: gpmf.FourCC = fourcc("GYRO");
pub const UNIT: gpmf.FourCC = fourcc("UNIT");
pub const SIUN: gpmf.FourCC = fourcc("SIUN");
pub const YAVG: gpmf.FourCC = fourcc("YAVG");
pub const HUES: gpmf.FourCC = fourcc("HUES");
pub const UNIF: gpmf.FourCC = fourcc("UNIF");
pub const WBAL: gpmf.FourCC = fourcc("WBAL");
pub const SHUT: gpmf.FourCC = fourcc("SHUT");
pub const ISOE: gpmf.FourCC = fourcc("ISOE");
pub const CORI: gpmf.FourCC = fourcc("CORI");
pub const IORI: gpmf.FourCC = fourcc("IORI");
pub const MWET: gpmf.FourCC = fourcc("MWET");
pub const WNDM: gpmf.FourCC = fourcc("WNDM");

fn fourcc(s: []const u8) gpmf.FourCC {
    return [4]u8{ s[0], s[1], s[2], s[3] };
}

test fourcc {
    try testing.expectEqual("GPMF".*, gpmf.FourCC{ 'G', 'P', 'M', 'F' });
    try testing.expectEqual(fourcc("GPMF"), gpmf.FourCC{ 'G', 'P', 'M', 'F' });
}
