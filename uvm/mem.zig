const std = @import("std");

const DataRow = struct { slice: []u32, addr: [*]u32 };

pub const MemList: type = struct {
    allocator: std.mem.Allocator,
    list: std.MultiArrayList(DataRow),
    zero: [*]u32,

    //
    // allocate a new empty row into the MemList
    //
    pub fn allocateRow(ml: *MemList, len: u32) ![]u32 {
        const slice = try ml.allocator.alloc(u32, len);
        try ml.list.append(ml.allocator, DataRow{
            .slice = slice,
            .addr = slice.ptr,
        });
        return slice;
    }

    //
    // copy the given array into the MemList
    // return a slice pointing to the new copy of the array
    //
    pub fn addRow(ml: *MemList, values: []const u32) ![]u32 {
        const slice = try ml.allocator.alloc(u32, values.len);
        @memcpy(slice, values);
        try ml.list.append(ml.allocator, DataRow{
            .slice = slice,
            .addr = slice.ptr,
        });
        return slice;
    }

    //
    // delete and free one row (an array of data) from the MemList
    // given a pointer to the array
    //
    pub fn freeRow(ml: *MemList, ptr: [*]u32) void {
        for (ml.list.items(.slice), 0..) |slice, i| {
            if (slice.ptr == ptr) {
                ml.list.swapRemove(i);
                ml.allocator.free(slice);
            }
        }
    }

    pub fn print(ml: *MemList) void {
        for (ml.list.items(.slice), 0..) |slice, i| {
            std.debug.print("Row {}: {*} (addr: {*})\n", .{ i, slice, slice.ptr });
        }
    }
};

pub fn init(allocator: std.mem.Allocator) !*MemList {
    const ml = try allocator.create(MemList);
    ml.* = .{
        .allocator = allocator,
        .list = std.MultiArrayList(DataRow){},
        .zero = undefined,
    };

    try ml.list.ensureTotalCapacity(allocator, 10);

    return ml;
}

pub fn initWithSlice(allocator: std.mem.Allocator, slice: []u32) !*MemList {
    const ml = try init(allocator);

    try ml.list.append(allocator, DataRow{
        .slice = slice,
        .addr = slice.ptr,
    });

    ml.zero = slice.ptr;

    return ml;
}

pub fn deinit(ml: *MemList) void {
    for (ml.list.items(.slice)) |slice| {
        ml.allocator.free(slice);
    }
    ml.list.deinit(ml.allocator);
    ml.allocator.destroy(ml);
}

test "mem" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ml = try init(allocator);
    defer deinit(ml);

    const slice1 = try ml.addRow(&[_]u32{ 1, 2, 3 });
    _ = try ml.addRow(&[_]u32{ 4, 5, 6 });
    const slice3 = try ml.addRow(&[_]u32{ 7, 8, 9 });

    ml.print();
    ml.freeRow(slice1.ptr);
    ml.freeRow(slice3.ptr);
    ml.print();
}

test "mem initWithSlice" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var array = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const slice = try allocator.alloc(u32, array.len);
    @memcpy(slice, array[0..]);
    const ml = try initWithSlice(allocator, slice);
    defer deinit(ml);

    const slice2 = try ml.addRow(&[_]u32{ 1, 2, 3 });
    const slice3 = try ml.addRow(&[_]u32{ 7, 8, 9 });

    ml.print();
    ml.freeRow(slice3.ptr);
    ml.freeRow(slice2.ptr);
    ml.print();
}

pub fn multiArrayListExamples(allocator: std.mem.Allocator) !void {
    var list = std.MultiArrayList(DataRow){};

    defer {
        // Free all slices when we're done
        const slices = list.items(.slice);
        const addrs = list.items(.addr);
        for (slices, addrs) |slice, addr| {
            std.debug.print("Freeing slice {*} (addr: {*})\n", .{ slice, addr });
            allocator.free(slice);
        }
        list.deinit(allocator);
        //allocator.free(list);
    }

    // Pre-allocate space
    try list.ensureTotalCapacity(allocator, 10);

    // Helper function to create a row
    const createRow = struct {
        fn create(alloc: std.mem.Allocator, values: []const u32) !DataRow {
            const slice = try alloc.alloc(u32, values.len);
            @memcpy(slice, values);
            return DataRow{
                .slice = slice,
                .addr = slice.ptr,
            };
        }
    }.create;

    // Add some rows
    try list.append(allocator, try createRow(allocator, &[_]u32{ 1, 2, 3 }));
    try list.append(allocator, try createRow(allocator, &[_]u32{ 4, 5, 6 }));
    try list.append(allocator, try createRow(allocator, &[_]u32{ 7, 8, 9 }));

    // Insert at specific index
    try list.insert(allocator, 1, try createRow(allocator, &[_]u32{ 42, 43 }));

    // Access specific fields
    const all_data = list.items(.slice);
    const all_addrs = list.items(.addr);

    // Print everything
    for (all_data, all_addrs, 0..) |data, addr, i| {
        std.debug.print("Row {}: {*} (addr: {*})\n", .{ i, addr, addr });
        std.debug.print("  Data: ", .{});
        for (data) |val| {
            std.debug.print("{} ", .{val});
        }
        std.debug.print("\n", .{});
    }

    // Get a specific row
    if (list.len > 0) {
        const row = list.get(0);
        std.debug.print("First row addr: {*}\n", .{row.addr});
    }

    // Swap remove (fast remove that doesn't preserve order)
    if (list.len > 1) {
        const row = list.get(1);
        list.swapRemove(1);
        allocator.free(row.slice);
    }

    // Ordered remove (preserves order but slower)
    if (list.len > 0) {
        const row = list.get(0);
        list.orderedRemove(0);
        allocator.free(row.slice);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    multiArrayListExamples(allocator) catch |err| {
        std.debug.panic("Error: {}", .{err});
    };
}
