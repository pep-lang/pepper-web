# (b) main as-is: `web.serve`, a router per request. Usage: server_b <port>

import async;
import http;
import io;
import web;
import "bench_app";

main(args: String[]): int {
    var port = args[1];
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse($"127.0.0.1:{port}").value()).value();
        web.serve(server, routes);
    });
    return 0;
}
