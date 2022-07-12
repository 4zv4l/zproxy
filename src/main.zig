const std = @import("std");
const net = std.net;
const heap = std.heap;
const thread = std.Thread;
const process = std.process;
const fmt = std.fmt;
const print = std.debug.print;

// show to user how to use the program
pub fn usage(file: []const u8) void {
    print("usage: {s} [input [port]] [destination [ip] [port]]\n", .{file});
    print("\n\tex: {s} 8080 anotherWebsite.com 80\n", .{file});
}

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
pub fn copy(in: net.Stream, out_addr: net.Address) void {
    // close the connection after this function end
    defer {
        in.close();
        print("[+] client disconnected\n", .{});
    }

    // connect to server
    const out = net.tcpConnectToAddress(out_addr) catch {
        print("[-] connect to {}\n", .{out_addr});
        _ = in.writer().writeAll("[-] couldn't connect\n") catch {};
        return;
    };
    print("[+] connect to {}\n", .{out_addr});
    defer out.close();

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

pub fn main() void {
    // init allocator
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // get argv
    const argv = process.argsAlloc(allocator) catch {
        print("[-] couldn't alloc main arguments..\n", .{});
        return;
    };
    defer process.argsFree(allocator, argv);

    // parse arguments
    if (argv.len != 4) {
        usage(argv[0]);
        return;
    }

    // setup input and output ip:port
    const in_ip = "0.0.0.0";
    const in_port = argv[1];
    const out_ip = argv[2];
    const out_port = argv[3];

    // setup listen_addr
    var port = fmt.parseUnsigned(u16, in_port, 10) catch {
        print("[-] not a number: {s}\n", .{in_port});
        return;
    };
    const in_addr = net.Address.parseIp(in_ip, port) catch {
        print("[-] address error: {s}:{}\n", .{ in_ip, port });
        return;
    };

    // setup output_addr
    port = fmt.parseUnsigned(u16, out_port, 10) catch {
        print("[-] not a number: {s}\n", .{in_port});
        return;
    };
    const out_addr = net.Address.parseIp(out_ip, port) catch {
        print("[-] address error: {s}:{}\n", .{ out_ip, port });
        return;
    };

    // listen on input_addr
    var input = net.StreamServer.init(.{ .reuse_address = true });
    defer input.deinit();
    input.listen(in_addr) catch {
        print("[-] listening\n", .{});
        return;
    };
    print("[+] Listening on {}\n", .{in_addr});

    // main loop catching clients
    while (true) {
        // get client
        const conn = input.accept() catch |e| {
            print("[-] accepting a client: {}\n", .{e});
            continue;
        };
        print("[+] accepting a client: {}\n", .{conn.address});
        const cli = conn.stream;

        // thread to handle the client
        const t = thread.spawn(.{}, copy, .{ cli, out_addr }) catch {
            print("[-] thread for client: {}\n", .{conn.address});
            continue;
        };
        print("[+] thread for client: {}\n", .{conn.address});
        t.detach();
    }
}
