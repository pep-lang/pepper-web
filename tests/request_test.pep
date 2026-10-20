# What a handler reads from a request: the query, cookies, forms
# (urlencoded and multipart) and JSON; and the cookies it sets.

import http;
import json;
import time;
import web;

context(method: String, url: String): web.Context {
    return web.Context(http.Request(method, url));
}

[Test]
reads_query_parameters() {
    var c = context("GET", "/search?q=pepper+lang&page=2&tag=a&tag=b&empty");
    expect_equal(c.query("q").value(), "pepper lang");
    expect_equal(c.query("page").value(), "2");
    expect_equal(c.query("tag").value(), "a");
    expect_equal(c.query("empty").value(), "");
    expect_true(c.query("missing").is_empty());
    expect_equal(c.query_pairs().count, 5 as ulong);
}

[Test]
treats_a_bad_query_as_empty() {
    var c = context("GET", "/search?q=%zz");
    expect_true(c.query("q").is_empty());
}

[Test]
reads_cookies() {
    var c = context("GET", "/");
    c.request.headers["Cookie"] = "session=abc123; theme=\"dark\"; flag";
    expect_equal(c.cookie("session").value(), "abc123");
    expect_equal(c.cookie("theme").value(), "dark");
    expect_true(c.cookie("flag").is_empty());
    expect_true(c.cookie("missing").is_empty());
}

[Test]
parses_cookie_headers() {
    var pairs = web.parse_cookies("a=1;b=2 ;  c = 3");
    expect_equal(pairs.count, 3 as ulong);
    expect_equal(pairs[1].0, "b");
    expect_equal(pairs[2].1, "3");
}

[Test]
writes_a_session_cookie() {
    expect_equal(web.Cookie("id", "7").to_string(), "id=7; Path=/");
}

[Test]
writes_cookie_attributes() {
    var cookie = web.Cookie("session", "abc");
    cookie.domain = "example.com";
    cookie.max_age = Optional<long>.Value(3600);
    cookie.expires = Optional<time.OffsetDateTime>.Value(time.OffsetDateTime.parse("2030-01-02T03:04:05Z").value());
    cookie.secure = true;
    cookie.http_only = true;
    cookie.same_site = web.SameSite.Strict;
    expect_equal(
        cookie.to_string(),
        "session=abc; Path=/; Domain=example.com; Max-Age=3600; Expires=Wed, 02 Jan 2030 03:04:05 GMT; Secure; HttpOnly; SameSite=Strict"
    );
    cookie.same_site = web.SameSite.Lax;
    expect_true(cookie.to_string().ends_with("; SameSite=Lax"));
    cookie.same_site = web.SameSite.None;
    expect_true(cookie.to_string().ends_with("; SameSite=None"));
}

[Test]
sets_cookies_on_a_response() {
    var response = web.text("ok");
    web.set_cookie(response, web.Cookie("a", "1"));
    web.set_cookie(response, web.Cookie("b", "2"));
    var fields = response.headers.values("Set-Cookie");
    expect_equal(fields.count, 2 as ulong);
    expect_equal(fields[1], "b=2; Path=/");
}

[Test]
[ShouldPanic("invalid cookie value")]
refuses_a_cookie_value_that_would_add_attributes() {
    web.Cookie("id", "7; Domain=evil.example").to_string();
}

[Test]
[ShouldPanic("invalid cookie name")]
refuses_a_cookie_name_with_a_newline() {
    web.Cookie("id\r\nX-Evil: 1", "7").to_string();
}

[Test]
parses_a_urlencoded_form() {
    var c = context("POST", "/signup");
    c.request.headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8";
    c.request.set_text("name=Ada+Lovelace&lang=pepper&lang=c&note=caf%C3%A9");
    var form = c.form().value();
    expect_equal(form.get("name").value(), "Ada Lovelace");
    expect_equal(form.get("note").value(), "café");
    var langs = form.get_all("lang");
    expect_equal(langs.count, 2 as ulong);
    expect_equal(langs[1], "c");
    expect_true(form.get("missing").is_empty());
    expect_equal(form.files.count, 0 as ulong);
}

[Test]
refuses_a_body_that_is_not_a_form() {
    var c = context("POST", "/signup");
    c.request.headers["Content-Type"] = "text/plain";
    c.request.set_text("name=Ada");
    expect_true(c.form().is_err());
    expect_true(context("POST", "/").form().is_err());
}

multipart(body: String): web.Context {
    var c = context("POST", "/upload");
    c.request.headers["Content-Type"] = "multipart/form-data; boundary=\"XyZ\"";
    c.request.set_text(body);
    return c;
}

[Test]
parses_a_multipart_form_with_a_file() {
    var body = "--XyZ\r\n"
        + "Content-Disposition: form-data; name=\"title\"\r\n"
        + "\r\n"
        + "My notes\r\n"
        + "--XyZ\r\n"
        + "Content-Disposition: form-data; name=\"upload\"; filename=\"notes.txt\"\r\n"
        + "Content-Type: text/plain\r\n"
        + "\r\n"
        + "line 1\r\nline 2\r\n"
        + "--XyZ\r\n"
        + "Content-Disposition: form-data; name=\"blank\"; filename=\"\"\r\n"
        + "\r\n"
        + "\r\n"
        + "--XyZ--\r\n";
    var form = multipart(body).form().value();
    expect_equal(form.get("title").value(), "My notes");
    expect_equal(form.files.count, 2 as ulong);
    var upload = form.file("upload").value();
    expect_equal(upload.file_name, "notes.txt");
    expect_equal(upload.content_type, "text/plain");
    expect_true(upload.data == "line 1\r\nline 2".bytes());
    var blank = form.file("blank").value();
    expect_equal(blank.file_name, "");
    expect_equal(blank.content_type, "application/octet-stream");
    expect_equal(blank.data.count, 0 as ulong);
    expect_true(form.file("title").is_empty());
}

[Test]
skips_a_multipart_preamble() {
    var body = "preamble\r\n--XyZ\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--XyZ--";
    expect_equal(multipart(body).form().value().get("a").value(), "1");
}

[Test]
keeps_binary_file_bytes() {
    var c = context("POST", "/upload");
    c.request.headers["Content-Type"] = "multipart/form-data; boundary=b";
    var body = "--b\r\nContent-Disposition: form-data; name=\"f\"; filename=\"x.bin\"\r\n\r\n".bytes();
    var data: u8[] = [0, 255, 13, 10, 45, 45, 0x80];
    body.append_all(data);
    body.append_all("\r\n--b--\r\n".bytes());
    c.request.set_body(body);
    expect_true(c.form().value().file("f").value().data == data);
}

[Test]
refuses_malformed_multipart_bodies() {
    expect_true(multipart("no boundary here").form().is_err());
    expect_true(multipart("--XyZ\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nunterminated").form().is_err());
    expect_true(multipart("--XyZ\r\nno blank line").form().is_err());
    expect_true(multipart("--XyZ\r\nContent-Type: text/plain\r\n\r\nx\r\n--XyZ--").form().is_err());
    var c = context("POST", "/upload");
    c.request.headers["Content-Type"] = "multipart/form-data";
    expect_true(c.form().is_err());
}

[Test]
parses_a_json_body() {
    var c = context("POST", "/items");
    c.request.set_text("{\"name\": \"pepper\", \"count\": 3}");
    var value = c.json().value();
    expect_equal(value["name"].as_string().value(), "pepper");
    expect_equal(value["count"].as_int().value(), 3);
    c.request.set_text("{oops");
    expect_true(c.json().is_err());
}

[Test]
writes_a_json_response() {
    var response = web.json_response(json.parse("{\"ok\": true}").value(), 201);
    expect_equal(response.status, 201);
    expect_equal(response.headers.get("Content-Type").value(), "application/json");
    expect_equal(response.text(), "{\"ok\":true}");
}
