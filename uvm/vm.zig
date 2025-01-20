const std = @import("std");
const fs = std.fs;
const util = @import("util.zig");
const mem = @import("mem.zig");
const ArrayList = std.ArrayList;

const State = struct {
    x: u32,
    opcode: Opcode,
    a: u3,
    b: u3,
    c: u3,

    pub fn init(self: *State, instruction: u32) void {
        self.x = instruction;
        const raw_opcode: u4 = @truncate(instruction >> 28);
        self.opcode = @enumFromInt(raw_opcode);
        self.a = @truncate((instruction >> 6) & 0x0007);
        self.b = @truncate((instruction >> 3) & 0x0007);
        self.c = @truncate(instruction & 0x0007);
    }
};

const Opcode = enum(u4) {
    ConditionalMove,
    ArrayIndex,
    ArrayAmendment,
    Addition,
    Multiplication,
    Division,
    NotAnd,
    Halt,
    Allocate,
    Abandon,
    Output,
    Input,
    LoadProgram,
    LoadConstant,

    pub fn disassemble(buf: []u8, instruction: u32) ![]const u8 {
        var state: State = undefined;
        state.init(instruction);

        switch (state.opcode) {
            .ConditionalMove => {
                const fmt = "{x}: if (R{x}) R{x} = R{x};";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.c, state.a, state.b });
            },
            .ArrayIndex => {
                const fmt = "{x}: R{x} = R{x}[R{x}];";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.a, state.b, state.c });
            },
            .ArrayAmendment => {
                const fmt = "{x}: R{x}[R{x}] = R{x};";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.a, state.b, state.c });
            },
            .Addition => {
                const fmt = "{x}: R{x} = R{x} + R{x};";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.a, state.b, state.c });
            },
            .Multiplication => {
                const fmt = "{x}: R{x} = R{x} * R{x};";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.a, state.b, state.c });
            },
            .Division => {
                const fmt = "{x}: R{x} = R{x} / R{x};";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.a, state.b, state.c });
            },
            .NotAnd => {
                const fmt = "{x}: R{x} = ~(R{x} & R{x});";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.a, state.b, state.c });
            },
            .Halt => {
                const fmt = "{x}: halt;";
                return std.fmt.bufPrint(buf, fmt, .{state.x});
            },
            .Allocate => {
                const fmt = "{x}: R{x} = (uint)alloc(size=R{x});";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.b, state.c });
            },
            .Abandon => {
                const fmt = "{x}: free(R{x});";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.c });
            },
            .Output => {
                const fmt = "{x}: putchar(R{x});";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.c });
            },
            .Input => {
                const fmt = "{x}: R{x} = getchar();";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.c });
            },
            .LoadProgram => {
                const fmt = "{x}: load(src = R{x}, ip =R{x});";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, state.b, state.c });
            },
            .LoadConstant => {
                const register = 7 & (state.x >> 25);
                const value = state.x & 0o177777777;
                const fmt = "{x}: R{x} = {x};";
                return std.fmt.bufPrint(buf, fmt, .{ state.x, register, value });
            },
        }
    }
};

const EMPTY_SLOT: []u32 = &[_]u32{};

pub const VM = struct {
    allocator: std.mem.Allocator,
    memory: std.ArrayList([]u32),
    reg: [8]u32,
    ip: u32,
    debug: bool,
};

pub fn initVM(allocator: std.mem.Allocator, input_data: []u32, debug: bool) !*VM {
    // Allocate memory for the VM struct
    const uvm = try allocator.create(VM);
    errdefer allocator.destroy(uvm);

    // Initialize the VM
    uvm.* = VM{
        .allocator = allocator,
        .memory = try ArrayList([]u32).initCapacity(allocator, 32),
        .reg = [_]u32{0} ** 8,
        .ip = 0,
        .debug = debug,
    };

    try uvm.memory.append(input_data);

    return uvm;
}

fn allocate_memory(uvm: *VM, size: u32) !u32 {
    const slot = uvm.memory.items.len;
    const block = try uvm.allocator.alloc(u32, size);
    @memset(block, 0);
    try uvm.memory.append(block);
    if (uvm.debug) std.debug.print("Allocated {d} bytes in slot {d}\n", .{ size, slot });
    return @intCast(slot);
}

pub fn fetch_memory_ptr(uvm: *VM, idx: u32) ![*]u32 {
    if (idx >= uvm.memory.items.len) {
        std.debug.print("Invalid memory index requested. requested: {x}, len: {x}\n", .{ idx, uvm.memory.items.len });
        return error.InvalidMemoryAccess;
    }
    return uvm.memory.items[idx].ptr;
}

pub fn runVM(uvm: *VM) !void {
    var buffer: [128]u8 = undefined;

    while (true) {
        const instruction = uvm.memory.items[0][uvm.ip];
        uvm.ip += 1;
        const raw_opcode: u4 = @truncate(instruction >> 28);
        const opcode: Opcode = @enumFromInt(raw_opcode);
        const a: u3 = @truncate((instruction >> 6) & 0x0007);
        const b: u3 = @truncate((instruction >> 3) & 0x0007);
        const c: u3 = @truncate(instruction & 0x0007);

        if (uvm.debug) {
            std.debug.print("IP: {d:0>3}, R:", .{(uvm.ip - 1)});
            for (uvm.reg) |reg| {
                std.debug.print("{x:0>8}|", .{reg});
            }
            std.debug.print("\n", .{});
            const result = try Opcode.disassemble(&buffer, instruction);
            std.debug.print("{s}\n", .{result});
        }

        switch (opcode) {
            .ConditionalMove => {
                if (uvm.reg[c] != 0) uvm.reg[a] = uvm.reg[b];
            },
            .ArrayIndex => {
                // case 1: reg[A] = arr(reg[B])[reg[C]]; break;
                const ptr = try fetch_memory_ptr(uvm, uvm.reg[b]);
                uvm.reg[a] = ptr[uvm.reg[c]];
            },
            .ArrayAmendment => {
                // case 2: arr(reg[A])[reg[B]] = reg[C];
                const ptr = try fetch_memory_ptr(uvm, uvm.reg[a]);
                ptr[uvm.reg[b]] = uvm.reg[c];
            },
            .Addition => {
                uvm.reg[a] = uvm.reg[b] +% uvm.reg[c];
            },
            .Multiplication => {
                uvm.reg[a] = uvm.reg[b] *% uvm.reg[c];
            },
            .Division => {
                uvm.reg[a] = uvm.reg[b] / uvm.reg[c];
            },
            .NotAnd => {
                uvm.reg[a] = ~(uvm.reg[b] & uvm.reg[c]);
            },
            .Halt => {
                return;
            },
            .Allocate => {
                // case 8: reg[B] = (uint)ulloc(reg[C]);
                const memory_slot = try allocate_memory(uvm, uvm.reg[c]);
                uvm.reg[b] = memory_slot;
            },
            .Abandon => {
                const slot = uvm.reg[c];
                const block = uvm.memory.items[slot];
                uvm.memory.items[slot] = EMPTY_SLOT;
                uvm.allocator.free(block);
            },
            .Output => {
                const value: u8 = @truncate(uvm.reg[c]);
                const out = std.io.getStdOut().writer();
                try out.print("{c}", .{value});
            },
            .Input => {
                const in = std.io.getStdIn().reader().readByte() catch 255;
                // not sure what to do with upper bits
                uvm.reg[c] = @intCast(in);
            },
            .LoadProgram => {
                if (uvm.reg[b] != 0) {
                    const srcSlot = uvm.reg[b];
                    const srcBlock = uvm.memory.items[srcSlot];
                    const newSlice = try uvm.allocator.alloc(u32, srcBlock.len);
                    @memcpy(newSlice, srcBlock);
                    const originalZero = uvm.memory.items[0];
                    uvm.memory.items[0] = newSlice;
                    uvm.allocator.free(originalZero);
                }
                uvm.ip = uvm.reg[c];
            },
            .LoadConstant => {
                uvm.reg[7 & (instruction >> 25)] = instruction & 0o177777777;
            },
        }
    }
}

pub fn freeVM(uvm: *VM) void {
    uvm.memory.deinit();
    uvm.allocator.destroy(uvm);
}
//};
