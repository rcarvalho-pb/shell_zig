const std = @import("std");

pub fn toUpper(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);
    for (input) |c| {
        try list.append(allocator, std.ascii.toUpper(c));
    }
    return list.toOwnedSlice(allocator);
}
