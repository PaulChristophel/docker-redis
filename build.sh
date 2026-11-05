#!/bin/sh
set -eu
jobs=${BUILD_JOBS:-4}

# Build Redis core and its bundled dependencies once. Conventional LLVM tool
# aliases on PATH also cover jemalloc's internal bitcode symbol discovery.
make -C src -j"${jobs}" all \
    CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no \
    ENABLE_LTO=-flto LDFLAGS=-fuse-ld=lld

llvm-nm --defined-only deps/jemalloc/lib/libjemalloc.a > /tmp/jemalloc-symbols
for symbol in malloc_with_usize calloc_with_usize realloc_with_usize free_with_usize get_defrag_hint; do
    grep -Eq " T je_${symbol}$" /tmp/jemalloc-symbols
done

# Use the module-only entry point: top-level make would enter core again.
make -C modules -j"${jobs}" all \
    CC=clang CXX=clang++ LD=lld AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no ENABLE_LTO=-flto \
    LDFLAGS=-fuse-ld=lld LTO=1 IGNORE_MISSING_DEPS=1 \
    REDISEARCH_GENERATE_HEADERS=0 INLINE_LSE_ATOMICS=0 \
    CMAKE_ARGS='-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O3 -DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O3'

for module in redisbloom/redisbloom redisearch/redisearch redisjson/rejson redistimeseries/redistimeseries; do
    test -s "modules/${module}.so"
done

# The TCP and TLS suites are separate test runs against the same build.
make -C src test \
    CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no \
    ENABLE_LTO=-flto LDFLAGS=-fuse-ld=lld
./utils/gen-test-certs.sh
./runtest --tls
