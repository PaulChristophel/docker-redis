#!/bin/sh
set -eu
jobs=${BUILD_JOBS:-4}

# Let Redis establish its saved settings and build the other dependencies first.
# LLVM tools are also on PATH under their conventional names: jemalloc's
# generated namespace discovery must be able to inspect LLVM bitcode with nm.
make -C src persist-settings \
    CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no \
    ENABLE_LTO=-flto LDFLAGS=-fuse-ld=lld

# Reproduce the separately validated jemalloc configuration explicitly.
(
    cd deps/jemalloc
    make distclean
    CC=clang AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
        CFLAGS='-O3 -flto' LDFLAGS='-flto -fuse-ld=lld' \
        ./configure --disable-cxx --with-version=5.3.0-0-g0 \
        --with-lg-quantum=3 --disable-cache-oblivious \
        --with-jemalloc-prefix=je_
    make -j"${jobs}" lib/libjemalloc.a
    llvm-nm --defined-only lib/libjemalloc.a > /tmp/jemalloc-symbols
    for symbol in malloc_with_usize calloc_with_usize realloc_with_usize free_with_usize get_defrag_hint; do
        grep -Eq " T je_${symbol}$" /tmp/jemalloc-symbols
    done
)

# Force a relink against the independently checked archive, preserving settings.
rm -f src/redis-server src/redis-sentinel src/redis-check-rdb src/redis-check-aof
make -C src -j"${jobs}" all \
    CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no \
    ENABLE_LTO=-flto LDFLAGS=-fuse-ld=lld

# Keep the manifest's portable ARM atomics setting and committed Rust headers.
make -j"${jobs}" \
    CC=clang CXX=clang++ LD=lld AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no ENABLE_LTO=-flto \
    LDFLAGS=-fuse-ld=lld LTO=1 IGNORE_MISSING_DEPS=1 \
    REDISEARCH_GENERATE_HEADERS=0 INLINE_LSE_ATOMICS=0 \
    CMAKE_ARGS='-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O3 -DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O3'

for module in redisbloom/redisbloom redisearch/redisearch redisjson/rejson redistimeseries/redistimeseries; do
    test -s "modules/${module}.so"
done

# Upstream test suites are build gates; smoke tests below cover the reduced
# filesystem and the four production modules, which make test does not load.
make -C src test \
    CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no \
    ENABLE_LTO=-flto LDFLAGS=-fuse-ld=lld
./utils/gen-test-certs.sh
./runtest --tls
