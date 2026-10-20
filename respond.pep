## Responses and middleware: `text`, `html`, `json_response` and
## `redirect` build common responses; `log_requests` is a middleware that
## logs each request.

import http;
import json;
import log;
import os;
import "router";

## Returns a response with `body` as `text/plain; charset=utf-8`.
##
## @param body the text
## @param status the status code
## @returns the response
export text(body: String, status: int = 200): http.Response {
    var response = http.Response(status).set_text(body);
    response.headers["Content-Type"] = "text/plain; charset=utf-8";
    return response;
}

## Returns a response with `body` as `text/html; charset=utf-8`.
##
## @param body the HTML
## @param status the status code
## @returns the response
export html(body: String, status: int = 200): http.Response {
    var response = http.Response(status).set_text(body);
    response.headers["Content-Type"] = "text/html; charset=utf-8";
    return response;
}

## Returns a response with `value` written as compact JSON, as
## `application/json`.
##
## @param value the JSON value
## @param status the status code
## @returns the response
export json_response(value: json.JsonValue, status: int = 200): http.Response {
    var response = http.Response(status).set_text(value.to_string());
    response.headers["Content-Type"] = "application/json";
    return response;
}

## Returns a redirect to `location`.
##
## @param location the URL to go to, absolute or relative to the request's
## @param status the status code: 303 See Other (the default) makes the
##   client follow with a `GET`; 307 and 308 keep the method; 301 and 302
##   are the older permanent and temporary forms
## @returns the response, with a `Location` field and no body
## @panics if `location` holds a CR, LF or NUL ("invalid redirect
##   location"), which would split the response; encode text from the
##   request (`Uri.encode`) before putting it in a URL
export redirect(location: String, status: int = 303): http.Response {
    var bytes = location.bytes();
    assert(!bytes.contains(13) && !bytes.contains(10) && !bytes.contains(0), "invalid redirect location");
    var response = http.Response(status);
    response.headers["Location"] = location;
    return response;
}

## A middleware that logs each request at the `info` level once it is
## answered, with its method, path, status and time in milliseconds, under
## the target `web`.
##
## @param context the request
## @param next the rest of the chain
## @returns `next`'s response
## @example
##     var router = web.Router().use(web.log_requests);
export log_requests(context: Context, next: Handler): http.Response {
    var start = os.Instant.now();
    var response = next(context);
    log.info(
        $"{context.request.method} {context.request.path()} {response.status}",
        [log.field("ms", start.elapsed().milliseconds())],
        "web"
    );
    return response;
}
