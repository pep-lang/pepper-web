# A keep-alive load generator: `client <port> <connections> <requests per
# connection>` sends GETs over each connection, one at a time, and prints the
# wall time per request.

import async;
import io;
import os;

const PATH = "/users/42/posts/7";

# Where the header block of `buffer` ends (after the blank line), or 0.
header_end(buffer: u8[]): ulong {
    ulong i = 3;
    while (i < buffer.count) {
        if (buffer[i] == 10 && buffer[i - 1] == 13 && buffer[i - 2] == 10 && buffer[i - 3] == 13) {
            return i + 1;
        }
        i = i + 1;
    }
    return 0;
}

# The Content-Length in the first `end` bytes of `buffer` (a lowercase or
# capitalized "ength: " followed by digits).
content_length(buffer: u8[], end: ulong): ulong {
    ulong i = 0;
    while (i + 8 < end) {
        if (buffer[i] == 101 && buffer[i + 1] == 110 && buffer[i + 2] == 103 && buffer[i + 3] == 116 && buffer[i + 4] == 104 && buffer[i + 5] == 58) {
            ulong j = i + 7;
            ulong value = 0;
            while (j < end && buffer[j] >= 48 && buffer[j] <= 57) {
                value = value * 10 + (buffer[j] - 48) as ulong;
                j = j + 1;
            }
            return value;
        }
        i = i + 1;
    }
    return 0;
}

# Reads one response from `stream`, keeping leftover bytes in `buffer`;
# whether it got one.
read_response(stream: io.TcpStream, buffer: u8[]): bool {
    while (true) {
        var end = header_end(buffer);
        if (end > 0) {
            var total = end + content_length(buffer, end);
            if (buffer.count >= total) {
                buffer.drain(0, total);
                return true;
            }
        }
        var n = stream.read(buffer, 65536);
        if (n.is_err() || n.value() == 0) {
            return false;
        }
    }
    return false;
}

main(args: String[]): int {
    var port = long.parse(args[1]).value();
    var connections = long.parse(args[2]).value() as ulong;
    var per = long.parse(args[3]).value() as ulong;
    const failures = async.Atomic<int>(0);
    var start = os.Instant.now();
    async.run(() => {
        var tasks = Array<async.Task<void>>();
        ulong c = 0;
        while (c < connections) {
            tasks.append(async.spawn<void>(() => {
                var stream = io.TcpStream.connect(io.SocketAddress.parse($"127.0.0.1:{port}").value()).value();
                var request = $"GET {PATH} HTTP/1.1\r\nHost: localhost\r\n\r\n".bytes();
                var buffer = Array<u8>();
                ulong i = 0;
                while (i < per) {
                    stream.write_all(request).value();
                    if (!read_response(stream, buffer)) {
                        failures.fetch_add(1);
                        return;
                    }
                    i = i + 1;
                }
            }));
            c = c + 1;
        }
        for (var task in tasks) {
            task.join();
        }
    });
    var total = connections * per;
    var us = start.elapsed().nanoseconds() as double / 1000.0 / total as double;
    print($"us_per_request {us} requests {total} failures {failures.load()}");
    return 0;
}
