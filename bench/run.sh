#!/usr/bin/env bash
# Benchmarks for pep-lang/pepper-web#2 (a router per request, per worker,
# per connection, or on router threads). Best of 9, alternating: every
# round runs every variant once. Build each, at -O, from this folder with
# -I <folder holding a `web` link to this repository>:
#   build_bench   (a) Router + routes() alone, and handle() alone
#   server_b_*    (b) web.serve as on main: a router per request
#   server_c_*    (c) a router per worker through raw memory (unsound; cost only)
#   server_d      (d) a router per connection: needs PEPPER_RUNTIME set to a
#                     0.11.1 runtime with serve_each.patch applied
#   server_e_*    (e) router threads behind a channel
# *_stock builds with the 0.11.1 runtime, *_mod with the patched one.
# client <port> <connections> <requests each> is the keep-alive load generator.
set -euo pipefail
cd "$(dirname "$0")"
variants="b_stock c_stock e_stock b_mod c_mod d"
port=18100
for round in 1 2 3 4 5 6 7 8 9; do
    ./build_bench.exe | sed "s/^/round $round build /"
    for v in $variants; do
        port=$((port + 1))
        ./server_$v.exe $port &
        pid=$!
        sleep 0.4
        ./client.exe $port 4 500 >/dev/null
        c1=$(./client.exe $port 1 10000)
        c16=$(./client.exe $port 16 3000)
        kill $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
        echo "round $round $v c1 $c1 | c16 $c16"
    done
done
