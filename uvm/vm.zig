const std = @import("std");
const fs = std.fs;
const util = @import("util.zig");
const mem = @import("mem.zig");
const MemList = mem.MemoryList;

const debug = true;

pub const VM = struct {
    allocator: std.mem.Allocator,
    memory: *MemList,
    zero: [*]u32,
    reg: [8]u32,
    ip: u32,
};

pub fn initVM(allocator: std.mem.Allocator, input_data: []u32) !*VM {
    // Allocate memory for the VM struct
    const uvm = try allocator.create(VM);
    errdefer allocator.destroy(uvm);

    // Initialize the VM
    uvm.* = VM{
        .allocator = allocator,
        .memory = try mem.initWithSlice(allocator, input_data),
        .zero = uvm.memory.list.items(.addr)[0],
        .reg = [_]u32{0} ** 8,
        .ip = 0,
    };

    return uvm;
}

fn allocate_memory(uvm: *VM, size: u32) ![]u32 {
    const row = try uvm.memory.allocateRow(size);
    if (debug) std.debug.print("Allocated {d} bytes for r{d}\n", .{ size, row[0] });
    return row[0..];
}

pub fn read_memory(uvm: *VM, addr: u32) ![*]u32 {
    if (addr == 0) {
        return uvm.zero;
    }
    return @as([*]u32, @ptrFromInt(addr));
}

pub fn runVM(uvm: *VM) !void {
    while (true) {
        const instruction = uvm.zero[uvm.ip];
        uvm.ip += 1;
        const opcode: u4 = @truncate(instruction >> 28);
        const a: u3 = @truncate((instruction >> 6) & 0x0007);
        const b: u3 = @truncate((instruction >> 3) & 0x0007);
        const c: u3 = @truncate(instruction & 0x0007);

        if (debug) {
            std.debug.print("IP: {d}, Instruction: 0x{x:0>2}, Op: {d}, A: {d}, B: {d}, C: {d}\n", .{ uvm.ip - 1, instruction, opcode, a, b, c });
            std.debug.print("Registers: {any}\n", .{uvm.reg});
        }

        switch (opcode) {
            0 => {
                if (uvm.reg[c] != 0) uvm.reg[a] = uvm.reg[b];
            },
            1 => uvm.reg[a] = read_memory(uvm, uvm.reg[b])[uvm.reg[c]],
            2 => read_memory(uvm, uvm.reg[a])[uvm.reg[b]] = uvm.reg[c],
            3 => uvm.reg[a] = uvm.reg[b] + uvm.reg[c],
            4 => uvm.reg[a] = uvm.reg[b] * uvm.reg[c],
            5 => uvm.reg[a] = uvm.reg[b] / uvm.reg[c],
            6 => uvm.reg[a] = ~uvm.reg[b] & uvm.reg[c],
            7 => return,
            8 => uvm.reg[b] = {
                const slice = try allocate_memory(uvm, uvm.reg[c]);
                uvm.zero[uvm.reg[b]] = @as(u32, slice.ptr);
            },
            9 => uvm.allocator.free(uvm.reg[c]),
            10 => std.io.getStdOut().writer().print("{c}", .{uvm.reg[c]}),
            11 => uvm.reg[c] = std.io.getStdIn().reader().readByte(),
            12 => if (uvm.reg[b] != null) {
                uvm.allocator.free(uvm.reg[b]);
                const size = uvm.reg[b][0];
                uvm.reg[c] = try allocate_memory(uvm, size);
                std.mem.copy(u32, uvm.reg[c], uvm.reg[b]);
                uvm.ip = uvm.reg[c];
            },
            13 => uvm.reg[7 & (instruction >> 25)] = instruction & 0o177777777,
            else => unreachable,
        }
    }
}

pub fn freeVM(uvm: *VM) void {
    uvm.allocator.free(uvm.memory);
    uvm.allocator.destroy(uvm);
}
//};
