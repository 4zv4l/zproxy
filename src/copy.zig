const std = @import("std");
const net = std.net;
const thread = std.Thread;
const print = std.debug.print;

/// get data from reader and write them to writer
/// until EOF
pub fn getAll(reader: net.Stream.Reader, writer: net.Stream.Writer) void {
    var buff: [1024]u8 = undefined;
    while (true) {
        // read from reader
        const data = reader.readUntilDelimiter(&buff, '\n') catch |e| switch (e) {
            // if error : write and read again until reaching '\n'
            error.StreamTooLong => {
                writer.writeAll(&buff) catch {
                    print("[-] sending data\n", .{});
                    return;
                };
                continue;
            },
            error.EndOfStream => return, // if conn closed
            else => return,
        };
        // if no error then write and break using isAgain
        writer.writeAll(buff[0 .. data.len + 1]) catch {
            print("[-] sending data\n", .{});
            return;
        };
    }
}

/// copy data from input to output
/// copy data from output to input
pub fn copyIO(in: net.Stream, out: net.Stream) void {
    // close the connection after this function end
    defer {
        in.close();
        out.close();
        print("[+] client disconnected\n", .{});
    }

    // reader/writer from input/output
    var in_r = in.reader();
    var in_w = in.writer();
    var out_r = out.reader();
    var out_w = out.writer();

    // send input data to output
    const t1 = thread.spawn(.{}, getAll, .{ in_r, out_w }) catch {
        print("[-] bridge connection\n", .{});
        return;
    };
    // send output data to input
    const t2 = thread.spawn(.{}, getAll, .{ out_r, in_w }) catch {
        print("[-] bridge connection\n", .{});
        return;
    };

    // wait for them
    t1.join();
    t2.join();
}
