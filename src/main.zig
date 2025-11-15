const std = @import("std");
const print = std.debug.print;

const Command = @import("command");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_writer.interface;

    const stdin_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(stdin_buffer);

    var stdin_reader = std.fs.File.stdin().readerStreaming(stdin_buffer);
    const stdin = &stdin_reader.interface;

    while (true) {
        try stdout.print("$ ", .{});
        const rawInput = try stdin.takeDelimiter('\n');
        if (rawInput) |input| {
            var command = Command.parseCommand(allocator, input) catch |err| {
                print("invalid command. error: {any}\n", .{err});
                continue;
            };
            defer command.deinit();
            switch (command.type) {
                // .NOT_FOUND => try handleNotFound(command),
                .EXIT => handleExit(command),
                // .TYPE => try handleType(command),
                // .PWD => try handlePWD(command),
                .ECHO => handleEcho(command),
                // .CD => try handleCD(command),
                else => {},
            }
        }
    }
}

// fn handleNotFound(command: Command.Command) !void {}
fn handleExit(command: Command.Command) void {
    if (command.getArguments()) |args| {
        if (args.len > 1) {
            print("invalid arguments\n", .{});
            return;
        }

        const code = std.fmt.parseInt(u8, args[0], 10) catch |err| {
            print("{any}\n", .{err});
            return;
        };

        std.process.exit(code);
    } else {
        print("invalid arguments\n", .{});
    }
}
// fn handleType(command: Command.Command) !void {}
// fn handlePWD(command: Command.Command) !void {}
fn handleEcho(command: Command.Command) void {
    if (command.getArguments()) |args| {
        for (args, 1..) |arg, i| {
            print("{s}", .{arg});
            if (i < args.len) {
                print(" ", .{});
            } else {
                print("\n", .{});
            }
        }
    }
}
// fn handleCD(command: Command.Command) !void {}

fn locateExecutable(allocator: std.mem.Allocator, executable: []const u8) !?[]const u8 {
    var envMap = try std.process.getEnvMap(allocator);
    defer envMap.deinit();
    const path = envMap.get("PATH");
    if (path) |p| {
        var folders = std.mem.splitScalar(u8, p, ':');
        while (folders.next()) |folder| {
            var dir = std.fs.cwd().openDir(folder, .{ .iterate = true }) catch continue;
            defer dir.close();
            var walker = try dir.walk(allocator);
            defer walker.deinit();
            while (try walker.next()) |entry| {
                if (std.mem.eql(u8, entry.basename, executable)) {
                    const exec = try std.fs.path.join(allocator, &[_][]const u8{ folder, entry.basename });
                    const stat = try std.fs.cwd().statFile(exec);
                    if ((stat.mode & 0o111) == 0) continue;
                    return exec;
                }
            }
        }
    }
    return null;
}
