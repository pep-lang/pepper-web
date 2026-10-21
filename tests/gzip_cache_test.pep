# The cache of gzipped static files: lookups by size and time, and dropping
# the least recently served bodies past its limit.

import "../gzip_cache";

bytes(count: ulong): u8[] {
    var data = Array<u8>();
    for (var i in 0..count) {
        data.append(i as u8);
    }
    return data;
}

[Test]
a_body_is_found_only_for_its_size_and_time() {
    var cache = _GzipCache(100);
    cache.put("a", 10, 5, bytes(3));
    expect_true(cache.get("a", 10, 5).value() == bytes(3));
    expect_true(cache.get("a", 11, 5).is_empty());
    expect_true(cache.get("a", 10, 6).is_empty());
    expect_true(cache.get("b", 10, 5).is_empty());
    cache.put("a", 11, 5, bytes(4));
    expect_true(cache.get("a", 11, 5).value() == bytes(4));
    expect_equal(cache.total, 4 as ulong);
}

[Test]
the_least_recently_served_bodies_are_dropped_past_the_limit() {
    var cache = _GzipCache(10);
    cache.put("a", 1, 1, bytes(4));
    cache.put("b", 1, 1, bytes(4));
    cache.get("a", 1, 1);
    cache.put("c", 1, 1, bytes(4));
    expect_true(cache.get("b", 1, 1).is_empty());
    expect_true(cache.get("a", 1, 1).is_value());
    expect_true(cache.get("c", 1, 1).is_value());
    expect_equal(cache.total, 8 as ulong);
    # Larger than the limit: not kept, and nothing else is dropped for it.
    cache.put("d", 1, 1, bytes(11));
    expect_true(cache.get("d", 1, 1).is_empty());
    expect_equal(cache.total, 8 as ulong);
}
