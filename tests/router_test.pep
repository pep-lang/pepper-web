# The router: routes, path parameters, wildcards, 404, 405 and 400, and
# middleware.

import http;
import io;
import log;
import web;

answer(router: web.Router, method: String, url: String): http.Response {
    return router.handle(http.Request(method, url));
}

users(): web.Router {
    var router = web.Router();
    router.get("/", (c) => web.text("home"));
    router.get("/users/{id}", (c) => web.text("user " + c.param("id")));
    router.post("/users/{id}", (c) => web.text("updated " + c.param("id")));
    router.get("/users/{id}/posts/{post}", (c) => web.text(c.param("id") + "/" + c.param("post")));
    router.get("/files/{*path}", (c) => web.text("file [" + c.param("path") + "]"));
    return router;
}

[Test]
matches_literal_paths() {
    var response = answer(users(), "GET", "/");
    expect_equal(response.status, 200);
    expect_equal(response.text(), "home");
    expect_equal(response.headers.get("Content-Type").value(), "text/plain; charset=utf-8");
}

[Test]
matches_path_parameters() {
    expect_equal(answer(users(), "GET", "/users/42").text(), "user 42");
    expect_equal(answer(users(), "GET", "/users/7/posts/hello").text(), "7/hello");
    expect_equal(answer(users(), "POST", "/users/42").text(), "updated 42");
}

[Test]
decodes_path_parameters() {
    expect_equal(answer(users(), "GET", "/users/caf%C3%A9%20au%20lait").text(), "user café au lait");
}

[Test]
ignores_the_query_when_matching() {
    expect_equal(answer(users(), "GET", "/users/42?tab=posts").text(), "user 42");
}

[Test]
matches_the_rest_of_the_path_with_a_wildcard() {
    expect_equal(answer(users(), "GET", "/files/a/b/c.txt").text(), "file [a/b/c.txt]");
    expect_equal(answer(users(), "GET", "/files/").text(), "file []");
}

[Test]
answers_404_when_no_route_matches() {
    var response = answer(users(), "GET", "/nothing");
    expect_equal(response.status, 404);
    expect_equal(answer(users(), "GET", "/users").status, 404);
    expect_equal(answer(users(), "GET", "/users/").status, 404);
    expect_equal(answer(users(), "GET", "/users/1/extra").status, 404);
}

[Test]
answers_405_with_allow_for_another_method() {
    var response = answer(users(), "DELETE", "/users/42");
    expect_equal(response.status, 405);
    expect_equal(response.headers.get("Allow").value(), "GET, HEAD, POST");
}

[Test]
answers_head_with_get_routes() {
    expect_equal(answer(users(), "HEAD", "/users/42").status, 200);
}

[Test]
answers_400_for_a_bad_escape() {
    expect_equal(answer(users(), "GET", "/users/%zz").status, 400);
}

[Test]
tries_routes_in_order() {
    var router = web.Router();
    router.get("/items/new", (c) => web.text("form"));
    router.get("/items/{id}", (c) => web.text("item " + c.param("id")));
    expect_equal(answer(router, "GET", "/items/new").text(), "form");
    expect_equal(answer(router, "GET", "/items/3").text(), "item 3");
}

[Test]
runs_middleware_outermost_first() {
    var router = web.Router();
    router.use((c, next) => {
        var response = next(c);
        response.headers.add("X-Trace", "outer");
        return response;
    });
    router.use((c, next) => {
        var response = next(c);
        response.headers.add("X-Trace", "inner");
        return response;
    });
    router.get("/", (c) => web.text("ok"));
    var trace = answer(router, "GET", "/").headers.values("X-Trace");
    expect_equal(trace.count, 2 as ulong);
    expect_equal(trace[0], "inner");
    expect_equal(trace[1], "outer");
}

[Test]
lets_middleware_answer_by_itself() {
    var router = web.Router();
    router.use((c, next) => {
        if (c.request.headers.get("Authorization").is_empty()) {
            return web.text("no", 401);
        }
        return next(c);
    });
    router.get("/secret", (c) => web.text("yes"));
    expect_equal(answer(router, "GET", "/secret").status, 401);
    var request = http.Request("GET", "/secret");
    request.headers["Authorization"] = "Bearer x";
    expect_equal(router.handle(request).text(), "yes");
}

[Test]
runs_middleware_around_404() {
    var router = web.Router();
    router.use((c, next) => {
        var response = next(c);
        response.headers["X-Seen"] = "1";
        return response;
    });
    var response = answer(router, "GET", "/missing");
    expect_equal(response.status, 404);
    expect_equal(response.headers.get("X-Seen").value(), "1");
}

[Test]
logs_requests() {
    # The log keeps its output for the program, so the leak check leaves
    # out what changing it allocates.
    var path = io.Directory.temp().join("pepper-web-log.log");
    keep_for_the_program(() => {
        var file = io.File.create(copy(path)).value();
        log.set_output(move(file));
    });
    var router = web.Router().use(web.log_requests);
    router.get("/users/{id}", (c) => web.text("ok"));
    expect_equal(answer(router, "GET", "/users/7").text(), "ok");
    keep_for_the_program(() => {
        log.set_output(io.File.stderr());
    });
    var logged = io.File.read_to_string(path).value();
    io.File.remove(path);
    expect_true(logged.contains(" INFO  [web] GET /users/7 200 ms="));
}

[Test]
builds_responses() {
    var page = web.html("<p>hi</p>", 201);
    expect_equal(page.status, 201);
    expect_equal(page.headers.get("Content-Type").value(), "text/html; charset=utf-8");
    var moved = web.redirect("/login");
    expect_equal(moved.status, 303);
    expect_equal(moved.headers.get("Location").value(), "/login");
}
