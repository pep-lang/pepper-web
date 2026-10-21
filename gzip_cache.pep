## The gzipped bodies `static_files` keeps in memory, so a text file is
## compressed once and not on every request.

import async;

## The most gzipped bytes `static_files` keeps in memory, over all files:
## 32 MiB. When a new body would pass it, the least recently served ones are
## dropped first.
export const MAX_GZIP_CACHE_SIZE: ulong = 33554432;

# One file's gzipped body, and the size and modification time of the file
# it was made from.
struct _GzipEntry {
    var size: ulong;
    var modified: long;
    var body: u8[];

    construct(size: ulong, modified: long, body: u8[]) {
        this.size = size;
        this.modified = modified;
        this.body = body;
    }
}

# Gzipped bodies by file path, least recently served first, holding at most
# `limit` bytes of them.
struct _GzipCache {
    var limit: ulong;
    var total: ulong;
    var entries: OrderedMap<String, _GzipEntry>;

    construct(limit: ulong) {
        this.limit = limit;
        this.total = 0;
        this.entries = OrderedMap<String, _GzipEntry>();
    }

    # The body of `path` when it was made from a file of `size` bytes
    # modified at `modified`, which becomes the most recently served.
    get(path: String, size: ulong, modified: long): u8[]? {
        var entry = entries.try_get(path);
        if (entry.is_empty() || entry.value().size != size || entry.value().modified != modified) {
            return Optional<u8[]>.Empty;
        }
        # Removing and inserting again moves it to the end.
        entries.remove(path);
        entries.insert(path, entry.value());
        return Optional<u8[]>.Value(entry.value().body);
    }

    # Keeps `body` as the body of `path`, replacing an older one, and drops
    # the least recently served bodies until all fit in `limit`. A body
    # larger than `limit` is not kept.
    put(path: String, size: ulong, modified: long, body: u8[]) {
        var old = entries.try_get(path);
        if (old.is_value()) {
            total = total - old.value().body.count;
            entries.remove(path);
        }
        if (body.count > limit) {
            return;
        }
        while (total + body.count > limit) {
            var first = entries.iterate();
            first.next();
            var (oldest, entry) = first.current();
            total = total - entry.body.count;
            entries.remove(oldest);
        }
        entries.insert(path, _GzipEntry(size, modified, body));
        total = total + body.count;
    }
}

const _gzip_cache = async.Mutex<_GzipCache>(_GzipCache(MAX_GZIP_CACHE_SIZE));
