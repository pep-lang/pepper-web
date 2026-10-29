import async;

# A table of handlers, like a router: not thread-safe.
struct Table {
    var handlers: Array<(String) => String>;

    construct() {
        handlers = Array<(String) => String>();
    }

    answer(input: String): String {
        return handlers[0](input);
    }
}

const tables = async.ThreadLocal<Table>();

serve(input: String): String {
    if (!tables.is_set()) {
        var table = Table();
        table.handlers.append((s) => s + "!");
        tables.set(move(table));
    }
    with (var table = tables.enter()) {
        return table.answer(input);   # VARIANT
    }
    return "";
}

main(): int {
    print(serve("hi"));
    return 0;
}
