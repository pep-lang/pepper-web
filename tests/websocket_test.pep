# A WebSocket route (pepper-websocket's `WebSocket.accept(request,
# handler)` in a handler) beside a plain route, on one port, through
# `web.serve`.

import async;
import http;
import io;
import tls;
import web;
import websocket;

chat_routes(router: web.Router) {
    router.get("/", (c) => web.text("home"));
    # Echoes WebSocket messages until the client closes.
    router.get("/chat", (c) => websocket.WebSocket.accept(c.request, (socket) => {
        while (true) {
            var message = socket.receive();
            if (message.is_err() || message.value().is_close()) {
                return;
            }
            socket.send_text("echo: " + message.value().text());
        }
    }));
}

[Test]
a_route_accepts_a_websocket_beside_plain_routes() {
    # The client sets up TLS once for the program (OpenSSL, on Linux and
    # macOS), which the leak check would count, as in static_test.pep.
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var port = server.local_address().value().port();
        async.spawn<void>(() => {
            web.serve(server, chat_routes);
        });
        var client = websocket.WebSocket.connect($"ws://127.0.0.1:{port}/chat").value();
        client.send_text("hello");
        expect_equal(client.receive().value().text(), "echo: hello");
        expect_true(client.close().is_ok());

        var page = http.Client().get($"http://127.0.0.1:{port}/").value();
        expect_equal(page.status, 200);
        expect_equal(page.text(), "home");
    });
}
