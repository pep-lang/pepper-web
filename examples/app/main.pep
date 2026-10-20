# An example web app: pages, a form, a cookie, a JSON API and static files.
#
#     pepper run -I packages examples/app/main.pep
#
# then open http://127.0.0.1:8080/ (run it from the repository's root, so
# that examples/app/public is found).

import async;
import http;
import io;
import json;
import web;

# Every thread's router counts into this one, which threads can share.
const signatures = async.Atomic<int>(0);

routes(router: web.Router) {
    router.use(web.log_requests);
    router.get("/", (c) => web.redirect("/static/index.html", 302));
    router.get("/static/{*path}", web.static_files(io.Path("examples/app/public")));
    router.post("/sign", sign);
    router.get("/hello/{name}", (c) => web.text($"Hello, {c.param("name")}!"));
    router.get("/api/stats", (c) => {
        var stats = json.parse("{}").value();
        stats["signatures"] = json.JsonValue.Integer(signatures.load());
        return web.json_response(stats);
    });
}

sign(c: web.Context): http.Response {
    var form = c.form();
    if (form.is_err()) {
        return web.text(form.error().message, 400);
    }
    var name = form.value().get("name").value_or("").trim();
    if (name.size == 0) {
        return web.text("a name, please", 400);
    }
    signatures.fetch_add(1);
    var response = web.html($"<p>Thanks, {escape(name)}!</p>");
    var cookie = web.Cookie("signed", "yes");
    cookie.http_only = true;
    cookie.same_site = web.SameSite.Lax;
    web.set_cookie(response, cookie);
    return response;
}

# `text` with the characters HTML treats specially written as entities.
escape(text: String): String {
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
}

main(): int {
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:8080").value()).value();
        print("listening on http://127.0.0.1:8080/");
        web.serve(server, routes);
    });
    return 0;
}
