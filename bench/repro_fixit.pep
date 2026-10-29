import async;

# Not copyable: a plain function value field.
struct Reply {
    var text: String;
    var callback: () => void;

    construct(text: String) {
        this.text = text;
        this.callback = () => {};
    }
}

const replies = async.ThreadLocal<Reply>();

latest(): Reply {
    replies.set(Reply("hi"));
    with (var reply = replies.enter()) {
        return copy(reply);
    }
    return Reply("");
}

main(): int {
    print(latest().text);
    return 0;
}
