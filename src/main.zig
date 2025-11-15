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
            command.writer = stdout;
            defer command.deinit();
            switch (command.type) {
                // .NOT_FOUND => try handleNotFound(command),
                .EXIT => handleExit(command),
                // .TYPE => try handleType(command),
                .PWD => handlePWD(command),
                .ECHO => handleEcho(command),
                .CD => handleCD(command),
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
fn handlePWD(command: Command.Command) void {
    const cwd = std.process.getCwdAlloc(command.allocator) catch {
        print("error getting pwd\n", .{});
        return;
    };
    defer command.allocator.free(cwd);
    command.writer.?.print("{s}\n", .{cwd}) catch {
        print("error finding pwd\n", .{});
    };
}

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
fn handleCD(command: Command.Command) void {
    const writer = command.writer orelse {
        print("writer not found\n", .{});
        return;
    };

    const args_opt = command.getArguments() orelse {
        writer.print("cd: missing argument\n", .{}) catch {};
        return;
    };

    const args = args_opt;
    if (args.len > 1) {
        writer.print("cd: too many arguments\n", .{}) catch {};
        return;
    }

    const arg = args[0];

    if (arg.len > 0 and arg[0] == '~') {
        var env = std.process.getEnvMap(command.allocator) catch {
            writer.print("cd: error reading environment\n", .{}) catch {};
            return;
        };
        defer env.deinit();

        const os = @import("builtin").os.tag;

        const home_env_var = if (os == .windows) "USERPROFILE" else "HOME";

        const home = env.get(home_env_var) orelse env.get("HOMEPATH") orelse {
            writer.print("cd: HOME not set\n", .{}) catch {};
            return;
        };

        const rest = if (arg.len > 1) arg[1..] else "";

        const full_path = std.fs.path.join(command.allocator, &[_][]const u8{ home, rest });
        if (full_path) |p| {
            defer command.allocator.free(p);
            changeDir(writer, p);
            return;
        } else |err| {
            print("err: {any}\n", .{err});
            writer.print("cd: {s}: No such file or directory\n", .{arg}) catch {};
            return;
        }
    }
    changeDir(writer, arg);
}

fn changeDir(writer: *std.io.Writer, path: []const u8) void {
    const dir = std.fs.cwd().openDir(path, .{});
    if (dir) |d| {
        d.setAsCwd() catch {
            writer.print("cd: error setting cwd\n", .{}) catch {};
            return;
        };
    } else |err| {
        print("err: {any}\n", .{err});
        writer.print("cd: {s}: No such file or directory\n", .{path}) catch {
            return;
        };
    }
}

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
