# pepper-web

A small web framework for [Pepper](https://github.com/pep-lang/pepper),
built on the runtime's `http.Server`: routing with path parameters,
middleware, cookies, form and query parsing, JSON, and static files.

One module, **`web`**:

- **`Router`** sends each request to the first route whose method and
  pattern match: `router.get("/users/{id}", handler)`, with `post`, `put`,
  `patch`, `delete` and `route(method, ...)`. `{name}` matches one path
  segment and `{*name}` the rest of the path; both are percent-decoded. A
  path no route matches gets `404`, one that matches only other methods
  `405` with `Allow`, and `HEAD` is answered by `GET` routes.
- **`Context`** is what a handler gets: `request`, `param(name)`,
  `query(name)`, `cookie(name)`, `form()` and `json()`.
- **Middleware** (`router.use(m)`) wraps every request, the 404s and 405s
  included: `m(context, next)` may answer by itself or call `next(context)`.
  `log_requests` logs each request through the runtime's `log`.
- **`web.serve(server, app)`** runs a router on an `http.Server`: `app`
  adds the routes to a new `Router`.
- **Responses**: `text`, `html`, `json_response` and `redirect`.
- **Cookies**: `Cookie` with `Path`, `Domain`, `Max-Age`, `Expires`,
  `Secure`, `HttpOnly` and `SameSite`, written with `set_cookie`; a
  name or value that could split the header panics.
- **Forms**: `parse_form` (and `context.form()`) reads
  `application/x-www-form-urlencoded` and `multipart/form-data`, with
  uploaded files as `FormFile`s.
- **Static files**: `static_files(root)` serves a folder from a
  `{*path}` route, with content types, `index.html` for folders, `ETag`
  and `If-None-Match` (`304`), single `Range` requests (`206`, `416`) with
  `If-Range`, and gzip for text when the client accepts it. It refuses
  any path that could leave `root`: `..` segments, absolute paths,
  backslashes, drive or stream names (`:`), and NULs, percent-encoded or
  not.

```pepper
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
```

This is [`examples/app/main.pep`](examples/app/main.pep); from the root of
this repository, with the package on the import path (see below), run it
with `pepper run -I packages examples/app/main.pep`.

## Threads

`http.Server` answers requests on every worker thread of `async.run`, and
a router and its handlers (plain closures) are not thread-safe. So
`web.serve` builds a router for each request by calling `app`: keep `app`
to adding routes, and keep state the handlers share in thread-safe values
at module scope, such as an `async.Atomic<T>` or a `[Shared]` struct.

## Limits

- The router is rebuilt for every request (see above, and
  pep-lang/pepper#63), which costs a few allocations per route.
- No recovery from panics: a panicking handler ends the program, as any
  panic does.
- Request bodies are read in full by `http.Server` (16 MiB at most), so
  uploads are held in memory.
- Static files: several ranges in one request get the whole file; no
  `Last-Modified` or `If-Modified-Since`; symbolic links inside the root
  are followed, and dotfiles are served like other files.
- No WebSocket upgrades from a route (pep-lang/pepper#47); use
  [pepper-websocket](https://github.com/pep-lang/pepper-websocket) on its
  own listener.

## Using it

This repository is a package: `pep.toml` marks its root, and its root
`module.pep` is the `web` module. Add it to a project under the name
`web`:

```sh
pepper package add pep-lang/pepper-web --name web
```

which writes

```toml
[dependencies]
web = { github = "pep-lang/pepper-web" }
```

Without a project, put a folder named `web` that holds (or links to) this
repository on the import path: `pepper build -I packages main.pep`.

## Tests

```sh
tests/run.sh path/to/pepper
```

runs the `[Test]` functions in `tests/` with `pepper test`, from the
repository's root: routing and middleware (`router_test.pep`); queries,
cookies, forms and JSON (`request_test.pep`); and static files over
loopback, path traversal included (`static_test.pep`, with files in
`tests/testdata/`). It then builds the example app.

## Releasing

CI (`.github/workflows/ci.yml`) runs the tests on Linux, macOS and
Windows for every push to `main` and every pull request. To release, set
`version` in `pep.toml`, merge, then push the matching tag
(`git tag v1.0.0 && git push origin v1.0.0`): CI tests the tag and
publishes a GitHub release for it. `pepper package add` and `pepper
package update` find versions by their tags.

## License

Apache-2.0; see [LICENSE](LICENSE).
