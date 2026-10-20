## Request bodies of HTML forms: `parse_form` reads
## `application/x-www-form-urlencoded` and `multipart/form-data` into a
## `Form` of fields and uploaded `FormFile`s.

import http;
import text;

## A file uploaded in a `multipart/form-data` body.
export struct FormFile {
    ## The form field's name.
    var name: String;
    ## The file name the client gave, as sent: never use it as a path on
    ## its own, since it may hold `/`, `\` or `..`.
    var file_name: String;
    ## The part's `Content-Type`; `application/octet-stream` when it has none.
    var content_type: String;
    ## The file's bytes.
    var data: u8[];

    ## Creates a file part.
    ##
    ## @param name the form field's name
    ## @param file_name the file name the client gave
    ## @param content_type the media type
    ## @param data the bytes
    construct(name: String, file_name: String, content_type: String, data: u8[]) {
        this.name = name;
        this.file_name = file_name;
        this.content_type = content_type;
        this.data = data;
    }
}

## The fields and files of a submitted form, in the order they were sent.
## A name may repeat.
export struct Form {
    ## The text fields, as names and values.
    var fields: Array<(String, String)>;
    ## The uploaded files (only `multipart/form-data` has any).
    var files: Array<FormFile>;

    ## Creates an empty form.
    construct() {
        fields = Array<(String, String)>();
        files = Array<FormFile>();
    }

    ## Returns the first value of the field `name`.
    ##
    ## @param name the field's name
    ## @returns its value, or none when the form has no such field
    get(name: String): String? {
        for (var field in fields) {
            if (field.0 == name) {
                return Optional<String>.Value(field.1);
            }
        }
        return Optional<String>.Empty;
    }

    ## Returns every value of the field `name`, such as the checked boxes of
    ## one group.
    ##
    ## @param name the field's name
    ## @returns the values in order; empty when there are none
    get_all(name: String): String[] {
        var values = Array<String>();
        for (var field in fields) {
            if (field.0 == name) {
                values.append(field.1);
            }
        }
        return values;
    }

    ## Returns the first file uploaded as the field `name`.
    ##
    ## @param name the field's name
    ## @returns the file, or none when the form has no such file
    file(name: String): FormFile? {
        for (var upload in files) {
            if (upload.name == name) {
                return Optional<FormFile>.Value(upload);
            }
        }
        return Optional<FormFile>.Empty;
    }
}

## Parses the body of `request` as a form, by its `Content-Type`:
## `application/x-www-form-urlencoded` (`+` is a space, percent-escapes are
## decoded) or `multipart/form-data` (RFC 7578), whose parts with a
## `filename` become `files` and the rest `fields`, decoded as UTF-8.
##
## @param request the request
## @returns the form; an error for another content type, a missing
##   boundary, an invalid percent-escape, or a multipart body that is not
##   well formed
export parse_form(request: http.Request): Result<Form> {
    var content_type = request.headers.get("Content-Type").value_or("");
    var media = content_type.split(";")[0].trim().lower();
    if (media == "application/x-www-form-urlencoded") {
        var pairs = Uri.decode_form(request.text());
        if (pairs.is_err()) {
            return Result<Form>.err(pairs.error());
        }
        var form = Form();
        form.fields = pairs.value();
        return Result<Form>.ok(form);
    }
    if (media == "multipart/form-data") {
        var boundary = _form_parameter(content_type, "boundary").value_or("");
        if (boundary.size == 0) {
            return Result<Form>.err(Error("multipart/form-data without a boundary"));
        }
        return _form_parse_multipart(request.body(), boundary);
    }
    return Result<Form>.err(Error($"not a form: Content-Type '{content_type}'"));
}

# The value of the parameter `name` in a header value such as
# `form-data; name="a"`, without quotes.
_form_parameter(header: String, name: String): String? {
    var pieces = header.split(";");
    ulong index = 1;
    while (index < pieces.count) {
        var piece = pieces[index].trim();
        var equals = piece.find("=");
        if (equals > 0 && piece.substr_bytes(0, equals as ulong).trim().lower() == name) {
            var value = piece.substr_bytes(equals as ulong + 1, piece.size - equals as ulong - 1).trim();
            if (value.size >= 2 && value.starts_with("\"") && value.ends_with("\"")) {
                value = value.substr_bytes(1, value.size - 2);
            }
            return Optional<String>.Value(value);
        }
        index = index + 1;
    }
    return Optional<String>.Empty;
}

# Splits a multipart body on `--boundary` lines into fields and files.
_form_parse_multipart(body: u8[], boundary: String): Result<Form> {
    var malformed = Result<Form>.err(Error("malformed multipart/form-data body"));
    var delimiter = ("\r\n--" + boundary).bytes();
    var form = Form();
    # The first delimiter may start the body, without the CRLF before it.
    ulong position = delimiter.count - 2;
    if (!_form_at(body, 0, delimiter.slice(2, delimiter.count).to_array())) {
        var first = _form_find(body, delimiter, 0);
        if (first.is_empty()) {
            return malformed;
        }
        position = first.value() + delimiter.count;
    }
    while (true) {
        # After a delimiter: `--` ends the body; otherwise CRLF and a part.
        if (_form_at(body, position, "--".bytes())) {
            return Result<Form>.ok(form);
        }
        if (!_form_at(body, position, "\r\n".bytes())) {
            return malformed;
        }
        position = position + 2;
        var head_end = _form_find(body, "\r\n\r\n".bytes(), position);
        if (head_end.is_empty()) {
            return malformed;
        }
        var head = text.Utf8.decode_lossy(body.slice(position, head_end.value()).to_array());
        var content_start = head_end.value() + 4;
        var next = _form_find(body, delimiter, content_start);
        if (next.is_empty()) {
            return malformed;
        }
        var data = body.slice(content_start, next.value()).to_array();
        var disposition = "";
        var content_type = "application/octet-stream";
        for (var line in head.split("\r\n")) {
            var colon = line.find(":");
            if (colon <= 0) {
                continue;
            }
            var field = line.substr_bytes(0, colon as ulong).trim().lower();
            var value = line.substr_bytes(colon as ulong + 1, line.size - colon as ulong - 1).trim();
            if (field == "content-disposition") {
                disposition = value;
            } else if (field == "content-type") {
                content_type = value;
            }
        }
        if (!disposition.lower().starts_with("form-data")) {
            return malformed;
        }
        var name = _form_parameter(disposition, "name").value_or("");
        var file_name = _form_parameter(disposition, "filename");
        if (file_name.is_value()) {
            form.files.append(FormFile(name, file_name.value(), content_type, data));
        } else {
            form.fields.append((name, text.Utf8.decode_lossy(data)));
        }
        position = next.value() + delimiter.count;
    }
    return malformed;
}

# Whether `data` holds `needle` at `position`.
_form_at(data: u8[], position: ulong, needle: u8[]): bool {
    if (position + needle.count > data.count) {
        return false;
    }
    ulong index = 0;
    while (index < needle.count) {
        if (data[position + index] != needle[index]) {
            return false;
        }
        index = index + 1;
    }
    return true;
}

# The position of the first `needle` in `data` at or after `from`.
# shortcut: a naive O(n*m) search, fine for form bodies under the server's
# 16 MiB limit with short boundaries; move to the runtime if it gets a
# byte-sequence search.
_form_find(data: u8[], needle: u8[], from: ulong): ulong? {
    var position = from;
    while (position + needle.count <= data.count) {
        if (_form_at(data, position, needle)) {
            return Optional<ulong>.Value(position);
        }
        position = position + 1;
    }
    return Optional<ulong>.Empty;
}
