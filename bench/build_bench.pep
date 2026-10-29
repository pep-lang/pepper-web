# (a) the cost of building the router, and of `handle` alone, in process.

import http;
import os;
import web;
import "bench_app";

const N: ulong = 200000;

main(): int {
    var sink: ulong = 0;
    var start = os.Instant.now();
    ulong i = 0;
    while (i < N) {
        var router = web.Router();
        routes(router);
        sink = sink + 1;
        i = i + 1;
    }
    var build = start.elapsed().nanoseconds() as double / N as double;
    var router = web.Router();
    routes(router);
    start = os.Instant.now();
    i = 0;
    while (i < N) {
        var response = router.handle(http.Request("GET", "/users/42/posts/7"));
        sink = sink + response.status as ulong;
        i = i + 1;
    }
    var handle = start.elapsed().nanoseconds() as double / N as double;
    print($"build_ns {build} handle_ns {handle} sink {sink}");
    return 0;
}
