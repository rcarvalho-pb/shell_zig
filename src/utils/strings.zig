const std = @import("std");

pub fn toUpper(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    for (input) |c| {
        try list.append(std.ascii.toUpper(c));
    }
    return list.toOwnedSlice();
}
