#!/bin/sh
set -eu

# Check the complete toolset before any expensive Redis/module compilation.
missing=no
for tool in sh bash make gcc g++ clang clang++ ld.lld lld llvm-ar llvm-ranlib llvm-nm \
    ar ranlib nm cmake git curl wget tar gzip bzip2 xz unzip rsync patch \
    autoconf autoheader automake aclocal libtoolize m4 pkg-config python3 \
    rustc cargo which find awk grep sed diff ps jq openssl tclsh strip readelf \
    ldd chroot install cp sort seq rpm zypper readlink; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing build tool: %s\n' "$tool" >&2
        missing=yes
    fi
done
[ "$missing" = no ]

rust_llvm=$(rustc -vV | sed -n 's/^LLVM version: \([0-9]*\).*/\1/p')
clang_llvm=$(clang --version | sed -n '1s/.*version \([0-9]*\).*/\1/p')
test -n "$rust_llvm"
test "$rust_llvm" = "$clang_llvm"
"${LD:-ld.lld}" --version | grep -E "LLD ${rust_llvm}\."
llvm-nm --version | grep -E "LLVM version ${rust_llvm}\."
/usr/bin/python3 -c 'import packaging, ssl, virtualenv'
python3 -m pip --version
# Tcl, rather than the shell, expands $result.
# shellcheck disable=SC2016
printf 'if {[catch {package require tls 1.6} result]} {puts stderr $result; exit 1}; puts $result\n' | tclsh
pkg-config --exists openssl libffi zlib
cmake --version

probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT HUP INT TERM

# Test extraction too: the source archive and nested module dependencies use tar.
mkdir -p "$probe_dir/input/nested" "$probe_dir/output"
printf 'archive probe\n' > "$probe_dir/input/nested/file"
tar -czf "$probe_dir/probe.tar.gz" -C "$probe_dir/input" nested
tar -xzf "$probe_dir/probe.tar.gz" -C "$probe_dir/output"
diff "$probe_dir/input/nested/file" "$probe_dir/output/nested/file"

cat > "$probe_dir/ssl.c" <<'C'
#include <openssl/ssl.h>
#include <crypt.h>
int main(void) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_method());
    if (ctx == NULL) return 1;
    SSL_CTX_free(ctx);
    return crypt("probe", "$6$probe$") == NULL;
}
C
clang -O3 -flto -fuse-ld=lld "$probe_dir/ssl.c" -lssl -lcrypto -lcrypt -o "$probe_dir/ssl"
"$probe_dir/ssl"

cat > "$probe_dir/cxx.cpp" <<'CXX'
#include <omp.h>
#include <thread>
int main() {
    std::thread worker([] {});
    worker.join();
    int (*volatile get_threads)() = omp_get_max_threads;
    return get_threads == nullptr;
}
CXX
clang++ -O3 -flto -fuse-ld=lld -pthread -fopenmp "$probe_dir/cxx.cpp" -o "$probe_dir/cxx"
"$probe_dir/cxx"

# openSUSE's libdispatch-devel provides Block.h in /usr/include/block.
cat > "$probe_dir/blocks.c" <<'C'
#include <Block.h>
int main(void) {
    int value = 42;
    int (^block)(void) = Block_copy(^{ return value; });
    int result = block();
    Block_release(block);
    return result != 42;
}
C
clang -O3 -flto -fuse-ld=lld -fblocks "$probe_dir/blocks.c" \
    -lBlocksRuntime -o "$probe_dir/blocks"
"$probe_dir/blocks"

# Exercise an actual Rust/C LTO link, not just compiler version strings.
printf 'int dependency_probe(void) { return 42; }\n' > "$probe_dir/probe.c"
clang -O3 -flto -c "$probe_dir/probe.c" -o "$probe_dir/probe.o"
llvm-ar rcs "$probe_dir/libdependency_probe.a" "$probe_dir/probe.o"
cat > "$probe_dir/probe.rs" <<'RUST'
extern "C" { fn dependency_probe() -> i32; }
fn main() { assert_eq!(unsafe { dependency_probe() }, 42); }
RUST
rustc --edition=2021 -C opt-level=3 -C linker-plugin-lto -C linker=clang \
    -C link-arg=-fuse-ld=lld -L "native=$probe_dir" -l static=dependency_probe \
    "$probe_dir/probe.rs" -o "$probe_dir/rust-c-lto"
"$probe_dir/rust-c-lto"

# Rust bindgen needs libclang's shared library, not only the clang executable.
libclang=$(find /usr/lib64 /usr/lib -name 'libclang.so*' -type f -print 2>/dev/null | head -n 1)
test -n "$libclang"
python3 -c 'import ctypes, sys; ctypes.CDLL(sys.argv[1])' "$libclang"
printf 'Build dependency checks passed (LLVM %s).\n' "$rust_llvm"
