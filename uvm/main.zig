const std = @import("std");
const fs = std.fs;
const util = @import("util.zig");
const vm = @import("vm.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try stdout.print("Please provide a filename as an argument!\n", .{});
        std.process.exit(1);
    }

    const exists = util.checkFileExists(args[1]) catch |err| {
        try stdout.print("Error accessing '{s}': {any}\n", .{ args[1], err });
        std.process.exit(1);
    };

    if (!exists) {
        try stdout.print("File '{s}' does not exist!\n", .{args[1]});
        std.process.exit(1);
    }

    const file_contents = try util.readFileToMem(allocator, args[1]);
    defer allocator.free(file_contents);
    try stdout.print("File '{s}' read.\n", .{args[1]});

    const debug = try util.getBooleanEnvVar(allocator, "UVM_DEBUG");

    const uvm = try vm.initVM(allocator, file_contents, debug);
    defer vm.freeVM(uvm);
    try vm.runVM(uvm);
}
