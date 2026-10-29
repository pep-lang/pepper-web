# (e) router-owning threads: each connection task sends the request to one
# of them over one channel and waits on a reply channel. Usage: server_e <port>

import async;
import http;
import io;
import web;
import "bench_app";

const ROUTER_THREADS: ulong = 8;

# One request for a router thread, and where its response goes.
struct Job {
    var request: http.Request;
    var reply: async.Channel<http.Response>;

    construct([Move] request: http.Request, reply: async.Channel<http.Response>) {
        this.request = request;
        this.reply = reply;
    }
}

# A copy of `response` that shares nothing with it (status, headers, body):
# `copy` refuses a Response, whose upgrade callback is a plain function.
detach(response: http.Response): http.Response {
    var out = http.Response(response.status);
    for (var name in response.headers.names()) {
        for (var value in response.headers.values(name)) {
            out.headers.add(copy(name), copy(value));
        }
    }
    out.set_body(copy(response.body()));
    return out;
}

main(args: String[]): int {
    var port = args[1];
    const jobs = async.Channel<Job>(256);
    var threads = Array<async.Thread>();
    ulong t = 0;
    while (t < ROUTER_THREADS) {
        threads.append(async.Thread.spawn(() => {
            var router = web.Router();
            routes(router);
            while (true) {
                var job = jobs.receive();
                if (job.is_err()) {
                    return;
                }
                var response = router.handle(job.value().request);
                job.value().reply.send(detach(response));
            }
        }));
        t = t + 1;
    }
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse($"127.0.0.1:{port}").value()).value();
        server.serve((request) => {
            var reply = async.Channel<http.Response>(1);
            jobs.send(Job(copy(request), reply));
            return reply.receive().value();
        });
    });
    return 0;
}
