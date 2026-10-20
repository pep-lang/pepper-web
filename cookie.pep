## Cookies (RFC 6265): `Cookie` and `set_cookie` write `Set-Cookie`;
## `parse_cookies` reads a `Cookie` field. `Context.cookie` reads one
## cookie of a request.

import http;
import time;

## The `SameSite` attribute of a cookie: whether the browser sends it with
## requests that other sites start.
export enum SameSite {
    ## No attribute; the browser's default applies (`Lax` in current ones).
    Default,
    ## Sent with top-level navigations from other sites, not with their
    ## subrequests.
    Lax,
    ## Sent only with requests this site starts.
    Strict,
    ## Sent with every request; browsers require `secure` with it.
    None,
}

## A cookie to set on the client, with its attributes. Write it into a
## response with `set_cookie`.
##
## @example
##     var session = web.Cookie("session", "abc123");
##     session.http_only = true;
##     session.secure = true;
##     session.same_site = web.SameSite.Lax;
##     session.max_age = Optional<long>.Value(3600);
##     web.set_cookie(response, session);
export struct Cookie {
    ## The name: an HTTP token (letters, digits and ``!#$%&'*+-.^_`|~``).
    var name: String;
    ## The value: printable ASCII except space, `"`, `,`, `;` and `\`.
    ## Encode other text first, such as with `Uri.encode`.
    var value: String;
    ## The `Path` attribute; empty for none (the browser uses the request's
    ## directory).
    var path: String;
    ## The `Domain` attribute; empty for none (only the host that set it).
    var domain: String;
    ## The `Max-Age` attribute in seconds; 0 or less deletes the cookie.
    ## None for a session cookie, unless `expires` is set.
    var max_age: long?;
    ## The `Expires` attribute; none for none.
    var expires: time.OffsetDateTime?;
    ## The `Secure` attribute: sent only over HTTPS.
    var secure: bool;
    ## The `HttpOnly` attribute: hidden from scripts in the page.
    var http_only: bool;
    ## The `SameSite` attribute.
    var same_site: SameSite;

    ## Creates a session cookie with path `/` and no other attributes.
    ##
    ## @param name the name
    ## @param value the value
    construct(name: String, value: String) {
        this.name = name;
        this.value = value;
        this.path = "/";
        this.domain = "";
        this.max_age = Optional<long>.Empty;
        this.expires = Optional<time.OffsetDateTime>.Empty;
        this.secure = false;
        this.http_only = false;
        this.same_site = SameSite.Default;
    }

    ## Returns the cookie as the value of a `Set-Cookie` field, such as
    ## `id=7; Path=/; Max-Age=60; HttpOnly`.
    ##
    ## @returns the field value
    ## @panics if `name`, `value`, `path` or `domain` has a character it may
    ##   not have ("invalid cookie ..."), since it could split the field or
    ##   add attributes
    to_string(): String {
        assert(name.size > 0 && _cookie_all(name, _cookie_token_byte), $"invalid cookie name '{name}'");
        assert(_cookie_all(value, _cookie_value_byte), $"invalid cookie value for '{name}'");
        assert(_cookie_all(path, _cookie_attribute_byte), $"invalid cookie path for '{name}'");
        assert(_cookie_all(domain, _cookie_attribute_byte), $"invalid cookie domain for '{name}'");
        var out = StringBuilder();
        out.append($"{name}={value}");
        if (path.size > 0) {
            out.append($"; Path={path}");
        }
        if (domain.size > 0) {
            out.append($"; Domain={domain}");
        }
        if (max_age.is_value()) {
            out.append($"; Max-Age={max_age.value()}");
        }
        if (expires.is_value()) {
            out.append($"; Expires={expires.value().to_http_date()}");
        }
        if (secure) {
            out.append("; Secure");
        }
        if (http_only) {
            out.append("; HttpOnly");
        }
        if (same_site == SameSite.Lax) {
            out.append("; SameSite=Lax");
        } else if (same_site == SameSite.Strict) {
            out.append("; SameSite=Strict");
        } else if (same_site == SameSite.None) {
            out.append("; SameSite=None");
        }
        return out.to_string();
    }
}

## Adds a `Set-Cookie` field for `cookie` to `response`.
##
## @param response the response
## @param cookie the cookie to set
## @panics as `Cookie.to_string` does
export set_cookie(response: http.Response, cookie: Cookie) {
    response.headers.add("Set-Cookie", cookie.to_string());
}

## Returns the names and values in a `Cookie` field, such as
## `a=1; b="two"`, in order. Surrounding double quotes are removed from a
## value; nothing is decoded. A piece without `=` is skipped.
##
## @param header the field's value
## @returns the pairs
export parse_cookies(header: String): Array<(String, String)> {
    var pairs = Array<(String, String)>();
    for (var piece in header.split(";")) {
        var equals = piece.find("=");
        if (equals < 0) {
            continue;
        }
        var name = piece.substr_bytes(0, equals as ulong).trim();
        var value = piece.substr_bytes(equals as ulong + 1, piece.size - equals as ulong - 1).trim();
        if (value.size >= 2 && value.starts_with("\"") && value.ends_with("\"")) {
            value = value.substr_bytes(1, value.size - 2);
        }
        if (name.size > 0) {
            pairs.append((name, value));
        }
    }
    return pairs;
}

# Whether every byte of `text` passes `allowed`.
_cookie_all(text: String, allowed: (u8) => bool): bool {
    for (var c in text.bytes()) {
        if (!allowed(c)) {
            return false;
        }
    }
    return true;
}

# RFC 7230 tchar.
_cookie_token_byte(c: u8): bool {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
        return true;
    }
    return "!#$%&'*+-.^_`|~".bytes().contains(c);
}

# RFC 6265 cookie-octet.
_cookie_value_byte(c: u8): bool {
    return c >= 0x21 && c <= 0x7E && c != '"' && c != ',' && c != ';' && c != '\\';
}

# RFC 6265 av-octet: any printable byte but `;`.
_cookie_attribute_byte(c: u8): bool {
    return c >= 0x20 && c <= 0x7E && c != ';';
}
