## A web framework over the runtime's `http.Server`: a router with path
## parameters, middleware, cookies, form and query parsing, and static
## files.
##
## Bring it in with `import web`. Build a `Router` of routes and
## middleware; `web.serve(server, app)` runs routers on an `http.Server`,
## calling `app` to set up a router for each request.
## A handler gets a `Context` (the request, its path parameters, and
## helpers for the query, cookies and body) and returns an `http.Response`.
##
## - `Router`, `Context`, `Handler`, `Middleware`, `serve`: routing
## - `text`, `html`, `json_response`, `redirect`, `log_requests`:
##   responses and a logging middleware
## - `Cookie`, `SameSite`, `set_cookie`, `parse_cookies`: cookies
## - `Form`, `FormFile`, `parse_form`: form bodies, multipart included
## - `static_files`, `content_type`, `MAX_GZIP_SIZE`: static files
##
## @example
##     import async;
##     import http;
##     import io;
##     import web;
##
##     app(router: web.Router) {
##         router.use(web.log_requests);
##         router.get("/hello/{name}", (c) => web.text("hello, " + c.param("name")));
##         router.get("/static/{*path}", web.static_files(io.Path("public")));
##     }
##
##     main(): int {
##         async.run(() => {
##             var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:8080").value()).value();
##             web.serve(server, app);
##         });
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "cookie";
import "form";
import "respond";
import "router";
import "static";

export Handler;
export Middleware;
export Context;
export Router;
export serve;
export text;
export html;
export json_response;
export redirect;
export log_requests;
export SameSite;
export Cookie;
export set_cookie;
export parse_cookies;
export FormFile;
export Form;
export parse_form;
export MAX_GZIP_SIZE;
export static_files;
export content_type;
