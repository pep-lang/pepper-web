# Static files: content types, folders, ETag and If-None-Match, ranges,
# gzip, and refusing paths that would leave the root. The bodies are read
# over loopback, through `web.serve` and `http.Client`, as a browser
# would get them.

import async;
import compress;
import http;
import io;
import tls;
import web;

routes(router: web.Router) {
    router.get("/static/{*path}", web.static_files(io.Path("tests/testdata/public")));
}

# Answers `request` with the router directly, as the server would.
answer(request: http.Request): http.Response {
    var router = web.Router();
    routes(router);
    return router.handle(request);
}

get(url: String): http.Response {
    return answer(http.Request("GET", url));
}

# Sends `requests` (whose urls are paths) to a server running `routes`,
# over loopback, and returns the responses.
fetch(requests: Array<http.Request>): Array<http.Response> {
    # The client sets up TLS once for the program (OpenSSL, on Linux and
    # macOS), which the leak check would count; the runtime's tests do the same.
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    var responses = Array<http.Response>();
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var port = server.local_address().value().port();
        async.spawn<void>(() => {
            web.serve(server, routes);
        });
        var client = http.Client();
        for (var request in requests) {
            request.url = $"http://127.0.0.1:{port}{request.url}";
            responses.append(client.send(request).value());
        }
    });
    return responses;
}

[Test]
serves_a_file_with_its_type_and_tag() {
    var response = fetch([http.Request("GET", "/static/hello.txt")])[0];
    expect_equal(response.status, 200);
    expect_equal(response.text(), "hello, world\n");
    expect_equal(response.headers.get("Content-Type").value(), "text/plain; charset=utf-8");
    expect_equal(response.headers.get("Accept-Ranges").value(), "bytes");
    expect_true(response.headers.get("ETag").value().starts_with("\"d-"));
    expect_true(response.headers.get("Content-Encoding").is_empty());
}

[Test]
serves_binary_files_as_they_are() {
    var response = fetch([http.Request("GET", "/static/pixel.png")])[0];
    expect_equal(response.headers.get("Content-Type").value(), "image/png");
    var expected: u8[] = [0x89, 'P', 'N', 'G', 13, 10, 0x1A, 10, 0, 1];
    expect_true(response.body() == expected);
}

[Test]
serves_index_html_for_a_folder() {
    var responses = fetch([http.Request("GET", "/static/"), http.Request("GET", "/static/docs")]);
    expect_equal(responses[0].text(), "<!doctype html><title>home</title>\n");
    expect_equal(responses[0].headers.get("Content-Type").value(), "text/html; charset=utf-8");
    expect_equal(responses[1].text(), "<p>docs</p>\n");
}

[Test]
answers_404_for_a_missing_file() {
    expect_equal(get("/static/missing.txt").status, 404);
    expect_equal(get("/static/docs/missing/").status, 404);
}

[Test]
refuses_paths_that_leave_the_root() {
    # Each of these would reach tests/testdata/secret.txt, or a file
    # outside the project, if it were joined to the root as it is.
    var attempts = [
        "/static/../secret.txt",
        "/static/docs/../../secret.txt",
        "/static/%2e%2e/secret.txt",
        "/static/%2E%2E/secret.txt",
        "/static/..%2fsecret.txt",
        "/static/..%2Fsecret.txt",
        "/static/..%5csecret.txt",
        "/static/..\\secret.txt",
        "/static/docs/%2e%2e%2f%2e%2e%2fsecret.txt",
        "/static//etc/passwd",
        "/static/%2fetc%2fpasswd",
        "/static/%5cWindows%5cwin.ini",
        "/static/C:%5cWindows%5cwin.ini",
        "/static/C:/Windows/win.ini",
        "/static/hello.txt%00.png",
        "/static/hello.txt::$DATA",
        # Windows drops trailing dots and spaces from names.
        "/static/..%20/secret.txt",
        "/static/.../secret.txt",
        "/static/.%2e%20/secret.txt",
    ];
    for (var url in attempts) {
        var response = get(url);
        expect_equal(response.status, 404);
        expect_false(response.text().contains("secret"));
    }
    # The same route still serves what is inside the root.
    expect_equal(get("/static/./hello.txt").status, 200);
    expect_equal(get("/static/docs/%2e/index.html").status, 200);
}

[Test]
answers_304_for_a_matching_etag() {
    var tag = get("/static/hello.txt").headers.get("ETag").value();
    var request = http.Request("GET", "/static/hello.txt");
    request.headers["If-None-Match"] = "\"other\", " + tag;
    var response = answer(request);
    expect_equal(response.status, 304);
    expect_equal(response.headers.get("ETag").value(), tag);
    request.headers["If-None-Match"] = "W/" + tag;
    expect_equal(answer(request).status, 304);
    request.headers["If-None-Match"] = "*";
    expect_equal(answer(request).status, 304);
    request.headers["If-None-Match"] = "\"other\"";
    expect_equal(answer(request).status, 200);
}

ranged(range: String): http.Request {
    var request = http.Request("GET", "/static/hello.txt");
    request.headers["Range"] = range;
    return request;
}

[Test]
serves_byte_ranges() {
    var responses = fetch([ranged("bytes=0-4"), ranged("bytes=7-"), ranged("bytes=-6"), ranged("bytes=7-1000")]);
    expect_equal(responses[0].status, 206);
    expect_equal(responses[0].text(), "hello");
    expect_equal(responses[0].headers.get("Content-Range").value(), "bytes 0-4/13");
    expect_equal(responses[1].text(), "world\n");
    expect_equal(responses[1].headers.get("Content-Range").value(), "bytes 7-12/13");
    expect_equal(responses[2].text(), "world\n");
    expect_equal(responses[3].text(), "world\n");
}

[Test]
answers_416_for_a_range_past_the_end() {
    var response = answer(ranged("bytes=13-"));
    expect_equal(response.status, 416);
    expect_equal(response.headers.get("Content-Range").value(), "bytes */13");
    expect_equal(answer(ranged("bytes=-0")).status, 416);
}

[Test]
ignores_ranges_it_does_not_serve() {
    # Several ranges, a malformed one, another unit: the whole file.
    for (var range in ["bytes=0-1,3-4", "bytes=4-2", "bytes=x-", "lines=1-2"]) {
        expect_equal(answer(ranged(range)).status, 200);
    }
    var request = ranged("bytes=0-4");
    request.headers["If-Range"] = "\"stale\"";
    expect_equal(answer(request).status, 200);
    request.headers["If-Range"] = get("/static/hello.txt").headers.get("ETag").value();
    expect_equal(answer(request).status, 206);
}

gzipped(url: String, accept: String): http.Request {
    var request = http.Request("GET", url);
    request.headers["Accept-Encoding"] = accept;
    return request;
}

[Test]
gzips_text_for_a_client_that_accepts_it() {
    var responses = fetch([gzipped("/static/hello.txt", "br, gzip;q=0.8"), gzipped("/static/hello.txt", "identity")]);
    var packed = responses[0];
    expect_equal(packed.headers.get("Content-Encoding").value(), "gzip");
    expect_equal(packed.headers.get("Vary").value(), "Accept-Encoding");
    expect_true(packed.headers.get("ETag").value().ends_with("-gz\""));
    expect_true(compress.Gzip.decompress(packed.body()).value() == "hello, world\n".bytes());
    expect_true(responses[1].headers.get("Content-Encoding").is_empty());
    expect_equal(responses[1].text(), "hello, world\n");
}

[Test]
does_not_gzip_when_refused_or_binary() {
    expect_true(answer(gzipped("/static/hello.txt", "gzip;q=0")).headers.get("Content-Encoding").is_empty());
    expect_true(answer(gzipped("/static/hello.txt", "gzip; q=0.000")).headers.get("Content-Encoding").is_empty());
    expect_true(answer(gzipped("/static/pixel.png", "gzip")).headers.get("Content-Encoding").is_empty());
    expect_equal(answer(gzipped("/static/hello.txt", "*")).headers.get("Content-Encoding").value(), "gzip");
}

[Test]
names_content_types() {
    expect_equal(web.content_type("site.CSS"), "text/css; charset=utf-8");
    expect_equal(web.content_type("a/b/app.js"), "text/javascript; charset=utf-8");
    expect_equal(web.content_type("logo.svg"), "image/svg+xml");
    expect_equal(web.content_type("archive.tar.gz"), "application/gzip");
    expect_equal(web.content_type("README"), "application/octet-stream");
}
