# (d) a router per connection, built in the connection's task.
# Needs runtime-mod (http.Server.serve_each). Usage: server_d <port>

import async;
import http;
import io;
import web;
import "bench_app";

main(args: String[]): int {
    var port = args[1];
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse($"127.0.0.1:{port}").value()).value();
        server.serve_each(() => {
            var router = web.Router();
            routes(router);
            return (request) => router.handle(request);
        });
    });
    return 0;
}
