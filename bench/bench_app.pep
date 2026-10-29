# A realistic app for the benchmarks: 24 routes and 3 middleware.

import http;
import web;

export routes(router: web.Router) {
    router.use(server_header);
    router.use(request_id);
    router.use(require_auth);
    router.get("/", (c) => web.text("home"));
    router.get("/health", (c) => web.text("ok"));
    router.get("/about", (c) => web.html("<p>about</p>"));
    router.get("/users", (c) => web.text("users"));
    router.post("/users", (c) => web.text("created", 201));
    router.get("/users/{id}", (c) => web.text($"user {c.param("id")}"));
    router.put("/users/{id}", (c) => web.text("updated"));
    router.delete("/users/{id}", (c) => web.text("deleted"));
    router.get("/users/{id}/posts", (c) => web.text("posts"));
    router.get("/users/{id}/posts/{post}", (c) => web.text($"post {c.param("post")}"));
    router.get("/posts", (c) => web.text("all posts"));
    router.post("/posts", (c) => web.text("new post", 201));
    router.get("/posts/{id}", (c) => web.text("a post"));
    router.patch("/posts/{id}", (c) => web.text("patched"));
    router.get("/posts/{id}/comments", (c) => web.text("comments"));
    router.post("/posts/{id}/comments", (c) => web.text("comment", 201));
    router.get("/tags", (c) => web.text("tags"));
    router.get("/tags/{tag}", (c) => web.text($"tag {c.param("tag")}"));
    router.get("/search", (c) => web.text(c.query("q").value_or("")));
    router.get("/admin", (c) => web.text("admin"));
    router.get("/admin/stats", (c) => web.text("stats"));
    router.get("/api/v1/items", (c) => web.text("items"));
    router.get("/api/v1/items/{id}", (c) => web.text($"item {c.param("id")}"));
    router.get("/files/{*path}", (c) => web.text(c.param("path")));
}

server_header(c: web.Context, next: web.Handler): http.Response {
    var response = next(c);
    response.headers.set("Server", "bench");
    return response;
}

request_id(c: web.Context, next: web.Handler): http.Response {
    var response = next(c);
    response.headers.set("X-Request-Id", "1");
    return response;
}

require_auth(c: web.Context, next: web.Handler): http.Response {
    if (c.request.path().starts_with("/admin") && c.request.headers.get("Authorization").is_empty()) {
        return web.text("unauthorized", 401);
    }
    return next(c);
}
