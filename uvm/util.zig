const std = @import("std");
const fs = std.fs;

pub fn checkFileExists(filename: []const u8) !bool {
    fs.cwd().access(filename, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return false,
            error.PermissionDenied => {
                return error.PermissionDenied;
            },
            else => {
                return err;
            },
        }
    };
    return true;
}

//
// read in a file and return as a u32 byte array
//
pub fn readFileToMem(allocator: std.mem.Allocator, filename: []const u8) ![]u32 {
    // Open the file
    const file = try fs.cwd().openFile(filename, .{});
    defer file.close();

    // Get the file size
    const file_size = try file.getEndPos();
    if (file_size % 4 != 0) {
        return error.InvalidFileSize;
    }
    
    // First allocate a u8 buffer
    const u8_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(u8_buffer);  // Free the temporary buffer

    // Allocate the final u32 buffer
    const u32_buffer = try allocator.alloc(u32, file_size / 4);
    errdefer allocator.free(u32_buffer);

    // Read into the u8 buffer
    const bytes_read = try file.readAll(u8_buffer); // TODO: check bytes_read
    if (bytes_read != file_size) {
        return error.UnexpectedEOF;
    }

    // Convert the bytes to u32s (assuming big-endian)
    for (0..file_size/4) |i| {
        u32_buffer[i] = @as(u32, u8_buffer[i * 4]) << 24 |
                       @as(u32, u8_buffer[i * 4 + 1]) << 16 |
                       @as(u32, u8_buffer[i * 4 + 2]) << 8 |
                       @as(u32, u8_buffer[i * 4 + 3]);
    }

    return u32_buffer;
}