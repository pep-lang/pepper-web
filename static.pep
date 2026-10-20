## Static files: `static_files` serves a folder with content types,
## `ETag` and `If-None-Match`, single `Range` requests, and gzip for text;
## `content_type` maps a file name to its media type.

import compress;
import http;
import io;
import "respond";
import "router";

## The largest file `static_files` compresses with gzip: 4 MiB. Larger
## files are sent as they are, streamed from disk.
export const MAX_GZIP_SIZE: ulong = 4194304;

## Returns a handler that serves the files under `root` for `GET` and
## `HEAD` routes whose pattern ends in `{*path}`: the file at `root`
## joined with the request's `path` parameter (`index.html` for a folder).
##
## It refuses a path that could leave `root` with `404 Not Found`: one
## with a `..` segment, an absolute path, a backslash, a drive or stream
## name (`:`), or a NUL, in plain or percent-encoded form (the router
## decodes the path before the handler checks it). It does not follow the
## path's symbolic links any differently from the system, so a link inside
## `root` that points outside it is served.
##
## A file is sent with the `Content-Type` that `content_type` gives, an
## `ETag` made from its size and modification time, and `Accept-Ranges:
## bytes`. A request whose `If-None-Match` lists the `ETag` gets `304 Not
## Modified`. A single `Range: bytes=...` gets `206 Partial Content` (or
## `416 Range Not Satisfiable`), unless an `If-Range` names another
## `ETag`; several ranges get the whole file. A text file (`text/*`, JSON,
## JavaScript, SVG, XML) of at most `MAX_GZIP_SIZE` bytes is gzipped for a
## client that accepts it, with `Vary: Accept-Encoding`.
##
## @param root the folder to serve
## @returns the handler
## @example
##     var router = web.Router();
##     router.get("/assets/{*path}", web.static_files(io.Path("public")));
export static_files(root: io.Path): Handler {
    return (context) => _static_serve(root, context);
}

## Returns the media type for a file name, by its extension: `text/html;
## charset=utf-8` for `.html`, `image/png` for `.png`, and the like.
##
## @param name the file name or path
## @returns the media type; `application/octet-stream` for an unknown
##   extension
export content_type(name: String): String {
    var dot = name.rfind(".");
    var extension = dot < 0 ? "" : name.substr_bytes(dot as ulong + 1, name.size - dot as ulong - 1).lower();
    return match (extension) {
        "html", "htm" => "text/html; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "js", "mjs" => "text/javascript; charset=utf-8",
        "json" => "application/json",
        "txt" => "text/plain; charset=utf-8",
        "md" => "text/markdown; charset=utf-8",
        "csv" => "text/csv; charset=utf-8",
        "xml" => "application/xml",
        "svg" => "image/svg+xml",
        "png" => "image/png",
        "jpg", "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "avif" => "image/avif",
        "ico" => "image/x-icon",
        "pdf" => "application/pdf",
        "wasm" => "application/wasm",
        "woff" => "font/woff",
        "woff2" => "font/woff2",
        "mp4" => "video/mp4",
        "webm" => "video/webm",
        "mp3" => "audio/mpeg",
        "zip" => "application/zip",
        "gz" => "application/gzip",
        else => "application/octet-stream",
    };
}

# The file under `root` that the decoded `path` names, or none when the
# path could leave `root`.
_static_resolve(root: io.Path, path: String): io.Path? {
    if (path.starts_with("/") || path.contains("\\") || path.contains(":") || path.bytes().contains(0)) {
        return Optional<io.Path>.Empty;
    }
    var file = root;
    for (var part in path.split("/")) {
        if (part == "..") {
            return Optional<io.Path>.Empty;
        }
        if (part.size > 0 && part != ".") {
            file = file.join(part);
        }
    }
    return Optional<io.Path>.Value(file);
}

_static_serve(root: io.Path, context: Context): http.Response {
    var resolved = _static_resolve(root, context.param("path"));
    if (resolved.is_empty()) {
        return text("Not Found", 404);
    }
    var path = resolved.value();
    if (path.is_directory()) {
        path = path.join("index.html");
    }
    var metadata = path.metadata();
    if (metadata.is_err() || !metadata.value().is_file) {
        return text("Not Found", 404);
    }
    var size = metadata.value().size;
    var media = content_type(path.to_string());
    var tag = $"\"{size:x}-{metadata.value().modified:x}\"";
    var request = context.request;
    var gzip = size <= MAX_GZIP_SIZE && _static_compressible(media) && _static_accepts_gzip(request.headers);
    if (gzip) {
        tag = tag.substr_bytes(0, tag.size - 1) + "-gz\"";
    }

    var response = http.Response(200);
    response.headers["Content-Type"] = media;
    response.headers["ETag"] = tag;
    response.headers["Accept-Ranges"] = "bytes";
    if (_static_compressible(media)) {
        response.headers["Vary"] = "Accept-Encoding";
    }
    var none_match = request.headers.get("If-None-Match");
    if (none_match.is_value() && _static_matches(none_match.value(), tag)) {
        response.status = 304;
        return response;
    }

    var range = request.headers.get("Range");
    var if_range = request.headers.get("If-Range");
    if (range.is_value() && !gzip && (if_range.is_empty() || if_range.value() == tag)) {
        var span = _static_range(range.value(), size);
        if (span.is_value()) {
            var (first, last) = span.value();
            if (first > last) {
                response.status = 416;
                response.headers["Content-Range"] = $"bytes */{size}";
                return response;
            }
            var file = io.File.open(path);
            if (file.is_err() || file.value().seek_start(first as long).is_err()) {
                return text("Internal Server Error", 500);
            }
            response.status = 206;
            response.headers["Content-Range"] = $"bytes {first}-{last}/{size}";
            return response.set_reader(file.value(), (last - first + 1) as long);
        }
    }

    if (gzip) {
        var data = io.File.read_bytes(path);
        if (data.is_err()) {
            return text("Internal Server Error", 500);
        }
        response.headers["Content-Encoding"] = "gzip";
        return response.set_body(compress.Gzip.compress(data.value()));
    }
    var file = io.File.open(path);
    if (file.is_err()) {
        return text("Internal Server Error", 500);
    }
    return response.set_reader(file.value(), size as long);
}

# Whether a response of media type `media` is worth compressing.
_static_compressible(media: String): bool {
    return media.starts_with("text/")
        || media.starts_with("application/json")
        || media.starts_with("application/xml")
        || media.starts_with("image/svg+xml");
}

# Whether `Accept-Encoding` lists gzip (or `*`) with a nonzero quality.
_static_accepts_gzip(headers: http.Headers): bool {
    for (var header in headers.values("Accept-Encoding")) {
        for (var item in header.split(",")) {
            var parts = item.split(";");
            var coding = parts[0].trim().lower();
            if (coding != "gzip" && coding != "*") {
                continue;
            }
            var refused = false;
            ulong index = 1;
            while (index < parts.count) {
                # q=0, q=0.0 and the like refuse it.
                var parameter = parts[index].trim().lower();
                if (parameter.starts_with("q=")
                    && parameter.substr_bytes(2, parameter.size - 2).replace("0", "").replace(".", "").size == 0) {
                    refused = true;
                }
                index = index + 1;
            }
            return !refused;
        }
    }
    return false;
}

# Whether an `If-None-Match` value (`*` or a list of tags, weak or not)
# names `tag`.
_static_matches(header: String, tag: String): bool {
    for (var item in header.split(",")) {
        var candidate = item.trim();
        if (candidate == "*" || candidate == tag || candidate == "W/" + tag) {
            return true;
        }
    }
    return false;
}

# The first and last byte of a single `bytes=` range of a file of `size`
# bytes; first > last when it cannot be satisfied. None for a header that
# is not one well-formed byte range, which is ignored.
_static_range(header: String, size: ulong): Optional<(ulong, ulong)> {
    if (!header.starts_with("bytes=") || header.contains(",")) {
        return Optional<(ulong, ulong)>.Empty;
    }
    var spec = header.substr_bytes(6, header.size - 6).trim();
    var dash = spec.find("-");
    if (dash < 0) {
        return Optional<(ulong, ulong)>.Empty;
    }
    var start_text = spec.substr_bytes(0, dash as ulong);
    var end_text = spec.substr_bytes(dash as ulong + 1, spec.size - dash as ulong - 1);
    var unsatisfiable = Optional<(ulong, ulong)>.Value((1, 0));
    if (start_text.size == 0) {
        # bytes=-N: the last N bytes.
        var suffix = ulong.parse(end_text);
        if (suffix.is_empty()) {
            return Optional<(ulong, ulong)>.Empty;
        }
        if (suffix.value() == 0 || size == 0) {
            return unsatisfiable;
        }
        var count = suffix.value() < size ? suffix.value() : size;
        return Optional<(ulong, ulong)>.Value((size - count, size - 1));
    }
    var start = ulong.parse(start_text);
    if (start.is_empty()) {
        return Optional<(ulong, ulong)>.Empty;
    }
    if (size == 0 || start.value() >= size) {
        return unsatisfiable;
    }
    var last = size - 1;
    if (end_text.size > 0) {
        var end = ulong.parse(end_text);
        if (end.is_empty() || end.value() < start.value()) {
            return Optional<(ulong, ulong)>.Empty;
        }
        if (end.value() < last) {
            last = end.value();
        }
    }
    return Optional<(ulong, ulong)>.Value((start.value(), last));
}
