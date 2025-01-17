const std = @import("std");
const fs = std.fs;
const util = @import("util.zig");
const mem = @import("mem.zig");
const ArrayList = std.ArrayList;

const debug = true;

const EMPTY_SLOT: []u32 = &[_]u32{};

pub const VM = struct {
    allocator: std.mem.Allocator,
    memory: std.ArrayList([]u32),
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
        .memory = try ArrayList([]u32).initCapacity(allocator, 32),
        .reg = [_]u32{0} ** 8,
        .ip = 0,
    };

    try uvm.memory.append(input_data);

    return uvm;
}

fn allocate_memory(uvm: *VM, size: u32) !u32 {
    const slot = uvm.memory.items.len;
    const block = try uvm.allocator.alloc(u32, size);
    try uvm.memory.append(block);
    if (debug) std.debug.print("Allocated {d} bytes in slot {d}\n", .{ size, slot });
    return @intCast(slot);
}

pub fn fetch_memory_ptr(uvm: *VM, idx: u32) ![*]u32 {
    return uvm.memory.items[idx].ptr;
}

pub fn runVM(uvm: *VM) !void {
    while (true) {
        const instruction = uvm.memory.items[0][uvm.ip];
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
            1 => {
                // case 1: reg[A] = arr(reg[B])[reg[C]]; break;
                const ptr = try fetch_memory_ptr(uvm, uvm.reg[b]);
                uvm.reg[a] = ptr[uvm.reg[c]];
            },
            2 => {
                // case 2: arr(reg[A])[reg[B]] = reg[C];
                const ptr = try fetch_memory_ptr(uvm, uvm.reg[a]);
                ptr[uvm.reg[b]] = uvm.reg[c];
            },
            3 => uvm.reg[a] = uvm.reg[b] + uvm.reg[c],
            4 => uvm.reg[a] = uvm.reg[b] * uvm.reg[c],
            5 => uvm.reg[a] = uvm.reg[b] / uvm.reg[c],
            6 => uvm.reg[a] = ~uvm.reg[b] & uvm.reg[c],
            7 => return,
            8 => { // Allocation
                // case 8: reg[B] = (uint)ulloc(reg[C]);
                const memory_slot = try allocate_memory(uvm, uvm.reg[c]);
                uvm.reg[b] = memory_slot;
            },
            9 => { // Abandonment
                const slot = uvm.reg[c];
                const block = uvm.memory.items[slot];
                uvm.memory.items[slot] = EMPTY_SLOT;
                uvm.allocator.free(block);
            },
            10 => { // Output
                const value: u8 = @truncate(uvm.reg[c]);
                const out = std.io.getStdOut().writer();
                try out.print("{c}", .{value});
            },
            11 => { // Input
                const in = std.io.getStdIn().reader().readByte() catch 255;
                // not sure what to do with upper bits
                uvm.reg[c] = @intCast(in);
            },
            12 => if (uvm.reg[b] != 0) {
                const srcSlot = uvm.reg[b];
                const srcBlock = uvm.memory.items[srcSlot];
                const newSlice = try uvm.allocator.alloc(u32, srcBlock.len);
                @memcpy(newSlice, srcBlock);
                const originalZero = uvm.memory.items[0];
                uvm.memory.items[0] = newSlice;
                uvm.allocator.free(originalZero);
                uvm.ip = uvm.reg[c];
            },
            13 => uvm.reg[7 & (instruction >> 25)] = instruction & 0o177777777,
            else => unreachable,
        }
    }
}

pub fn freeVM(uvm: *VM) void {
    uvm.memory.deinit();
    uvm.allocator.destroy(uvm);
}
//};
