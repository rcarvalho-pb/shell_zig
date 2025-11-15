const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const toUpper = @import("utils").toUpper;
const CommandType = enum { NOT_FOUND, CD, PWD, TYPE, ECHO, EXIT };
const Command = struct {
    allocator: std.mem.Allocator,
    type: CommandType,
    rawArguments: ?[][]const u8,
    const Self = @This();
    pub fn deinit(self: *Self) void {
        if (self.rawArguments) |args| {
            self.allocator.free(args);
        }
    }
    pub fn getArguments(self: Self) ?[][]const u8 {
        if (self.rawArguments) |args| {
            return args[1..];
        }
        return null;
    }
    pub fn toString(self: Self) void {
        print("Command: {s}\nAguments:\n", .{@tagName(self.type)});
        if (self.getArguments()) |args| {
            for (args, 0..) |arg, i| {
                print("\t{d} - {s}\n", .{ i, arg });
            }
        }
    }
};
pub fn parseCommand(allocator: std.mem.Allocator, rawInput: []const u8) !Command {
    if (rawInput.len < 1) return error.InvalidParseInput;
    const input = std.mem.trim(u8, rawInput, " ");
    var list = std.ArrayList([]const u8){};
    defer list.deinit(allocator);
    var inQuotes: bool = false;
    var start: ?usize = null;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (c == '\'') {
            if (inQuotes) {
                if (start) |s| try list.append(allocator, input[s..i]);
                start = null;
            } else {
                start = i + 1;
            }
            inQuotes = !inQuotes;
        } else if (c == ' ') {
            if (inQuotes) continue;
            if (start) |s| {
                if (i > s) try list.append(allocator, input[s..i]);
                start = null;
            }
        } else {
            if (start == null) start = i;
        }
    }
    if (start) |s| if (s < i) try list.append(allocator, input[s..i]);
    const arguments = try list.toOwnedSlice(allocator);
    const upperCommand = try toUpper(allocator, arguments[0]);
    defer allocator.free(upperCommand);
    const command = Command{ .allocator = allocator, .type = std.meta.stringToEnum(CommandType, upperCommand) orelse .NOT_FOUND, .rawArguments = arguments };
    return command;
}
test "parse simple command" {
    const allocator = testing.allocator;
    const buf = try allocator.alloc(u8, 1024);
    defer allocator.free(buf);
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();
    const bytes_written = try writer.write("teste    teste2 'teste3 teste   teste' teste4");
    var command = try parseCommand(allocator, buf[0..bytes_written]);
    defer command.deinit();
    try testing.expectEqual(CommandType.NOT_FOUND, command.type);
    if (command.rawArguments) |args| {
        try testing.expectEqual(@as(usize, 4), args.len);
        try testing.expectEqualStrings("teste", args[0]);
    }
}
test "parse online '' token" {
    const allocator = testing.allocator;
    const buf = try allocator.alloc(u8, 1024);
    defer allocator.free(buf);
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();
    const bytes_writen = try writer.write("'echo 123     aonde'");
    var command = try parseCommand(allocator, buf[0..bytes_writen]);
    defer command.deinit();
    try testing.expectEqual(CommandType.NOT_FOUND, command.type);
    if (command.rawArguments) |args| {
        try testing.expectEqual(@as(usize, 1), args.len);
        try testing.expectEqualStrings("echo 123     aonde", args[0]);
    }
}
test "parse empty arguments" {
    const allocator = testing.allocator;
    const buf = try allocator.alloc(u8, 1024);
    defer allocator.free(buf);
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();
    const bytes_writen = try writer.write("");
    try testing.expectError(error.InvalidParseInput, parseCommand(allocator, buf[0..bytes_writen]));
}
