# (c) a router per worker, reached through raw memory to get past the
# confinement check: the cost it would have if the compiler allowed it.
# Not sound in general; for measuring only. Usage: server_c <port>

import async;
import http;
import io;
import web;
import "bench_app";

extern void* calloc(ulong count, ulong size);

[ThreadLocal]
var _slot: __ptr<void>;

handle(request: http.Request): http.Response {
    if (_slot == __null) {
        _slot = calloc(1, 8);
        var router = web.Router();
        routes(router);
        __ptr<web.Router> slot = _slot;
        slot[0] = router;
    }
    __ptr<web.Router> slot = _slot;
    return slot[0].handle(request);
}

main(args: String[]): int {
    var port = args[1];
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse($"127.0.0.1:{port}").value()).value();
        server.serve(handle);
    });
    return 0;
}
