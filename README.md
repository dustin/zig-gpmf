# gopro metadata parser for zig

Recent GoPro cameras record a telemetry stream along with video that
contains quite a rich selection of data.

This library parses that stream and provides low level access to that
data (as well as some high level access to come common/tedious
parts).  [GoPro's own project][gpmfdocs] documents the format and
features therein.

You can read the [API documentation][apidoc] to make awesome things with this.

[gpmfdocs]: https://github.com/gopro/gpmf-parser
[apidoc]: https://dustin.github.io/zig-gpmf/
