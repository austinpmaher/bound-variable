const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "icfp-2024",
        .root_source_file = b.path("main.zig"),
        .target = b.host,
    });

    b.installArtifact(exe);
}
