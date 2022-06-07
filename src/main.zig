const std = @import("std");
const net = std.net;
const heap = std.heap;
const thread = std.Thread;
const process = std.process;
const fmt = std.fmt;
const print = std.debug.print;

pub fn usage(file: []const u8) void {
    print("usage: {s} [input [port]] [destination [ip] [port]]\n", .{file});
    print("\n\tex: {s} 8080 anotherWebsite.com 80\n", .{file});
}

pub fn parseArgs(argv: [][:0]const u8) void {
    if (argv.len != 4) {
        usage(argv[0]);
        process.exit(1);
    }
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
                    print("error when sending data\n", .{});
                    return;
                };
                continue;
            },
            error.EndOfStream => return, // if conn closed
            else => return,
        };
        // if no error then write and break using isAgain
        writer.writeAll(buff[0 .. data.len + 1]) catch {
            print("error when sending data\n", .{});
            return;
        };
    }
}

/// copy data from input to output
/// copy data from output to input
pub fn copy(input: net.Stream, output_addr: net.Address) !void {
    // connect to server
    const output = try net.tcpConnectToAddress(output_addr);
    defer output.close();

    // reader/writer from input/output
    var input_reader = input.reader();
    var input_writer = input.writer();
    var output_reader = output.reader();
    var output_writer = output.writer();
    // send input data to output
    const t1 = try thread.spawn(.{}, getAll, .{ input_reader, output_writer });
    // send output data to input
    const t2 = try thread.spawn(.{}, getAll, .{ output_reader, input_writer });
    // wait for them
    t1.join();
    t2.join();
}

pub fn main() !void {
    // init allocator
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // get argv
    const argv = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, argv);

    // parse arguments
    parseArgs(argv);

    // setup input and output ip:port
    const input_port = argv[1];
    const output_ip = argv[2];
    const output_port = argv[3];

    // setup listen_addr
    var port = try fmt.parseUnsigned(u16, input_port, 10);
    const input_addr = try net.Address.parseIp("0.0.0.0", port);

    // setup output_addr
    port = try fmt.parseUnsigned(u16, output_port, 10);
    const output_addr = try net.Address.parseIp(output_ip, port);

    // listen on input_addr
    var input = net.StreamServer.init(.{ .reuse_address = true });
    defer input.deinit();
    try input.listen(input_addr);

    // main loop catching clients
    while (true) {
        const client = try input.accept();
        const client_thread = try thread.spawn(.{}, copy, .{ client.stream, output_addr });
        client_thread.detach();
    }
    print("closing..\n", .{});
}
