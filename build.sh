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

# Keep module-specific flags out of the core and the other module toolchains.
build_module() {
    module=$1
    shift
    make -C modules -j"${jobs}" all SUBDIRS="$module" \
    CC=clang CXX=clang++ LD=ld.lld AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm \
    MALLOC=jemalloc BUILD_TLS=yes USE_SYSTEMD=no ENABLE_LTO=-flto \
    LDFLAGS=-fuse-ld=lld LTO=1 IGNORE_MISSING_DEPS=1 \
    REDISEARCH_GENERATE_HEADERS=0 INLINE_LSE_ATOMICS=0 \
    CMAKE_ARGS='-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O3 -DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O3' \
    "$@"
}

# Readies builds CC_FLAGS from its own components; setting CFLAGS alone does not
# enable Blocks. Preserve its includes/defines and extend the library set.
build_module redisbloom 'CC_FLAGS.opt=-O3 -flto -fblocks' LD_LIBS.ext=BlocksRuntime
# RediSearch expects the LLVM driver name and adds -fuse-ld=lld itself.
# Autoconf/libtool dependencies in the other modules need the ELF linker.
build_module redisearch LD=lld
build_module redisjson
# TimeSeries uses the same Clang Blocks cleanup macros. Command-line Readies
# extension libraries must retain its OpenSSL dependencies as well.
build_module redistimeseries 'CC_FLAGS.opt=-O3 -flto -fblocks' \
    'LD_LIBS.ext=ssl crypto BlocksRuntime'

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
