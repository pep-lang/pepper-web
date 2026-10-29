# Step 1: a router per worker in a ThreadLocal<Router>, handing it the
# request with move(request). Does not compile on 0.11.1 or 0.12.0-dev:
#
#   error: 'request' cannot be moved: its value shares objects with the rest of the program
#
# With copy(request) instead, the response is refused:
#
#   error: 'router.handle(copy(request))' is part of the value locked by 'routers' and cannot be returned from the block
#
# `var response = ...; return move(response);` gives "'response' cannot be
# moved: 'router' also references its value", and copy(response) gives
# "cannot copy 'Response' because it contains '(Connection) => void'"
# (pep-lang/pepper#292 for the misleading note).

import async;
import http;
import io;
import web;
import "bench_app";

const routers = async.ThreadLocal<web.Router>();

main(args: String[]): int {
    var port = args[1];
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse($"127.0.0.1:{port}").value()).value();
        server.serve((request) => {
            if (!routers.is_set()) {
                var router = web.Router();
                routes(router);
                routers.set(move(router));
            }
            with (var router = routers.enter()) {
                return router.handle(move(request));
            }
            return web.text("no router", 500);
        });
    });
    return 0;
}
