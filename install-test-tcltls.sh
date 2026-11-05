#!/bin/sh
set -eu
: "${TCLTLS_VERSION:?TCLTLS_VERSION is required}"
: "${TCLTLS_SHA256:?TCLTLS_SHA256 is required}"

# Redis 8.10's unmodified test harness requires TclTLS 1.x. This extension is
# builder-only; its original source archive is mirrored by Debian unchanged.
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
curl --fail --location --retry 3 \
    "https://deb.debian.org/debian/pool/main/t/tcltls/tcltls_${TCLTLS_VERSION}.orig.tar.gz" \
    -o "$build_dir/source.tar.gz"
printf '%s  %s\n' "$TCLTLS_SHA256" "$build_dir/source.tar.gz" | sha256sum -c -
mkdir "$build_dir/src"
tar -xzf "$build_dir/source.tar.gz" -C "$build_dir/src" --strip-components=1
tcl_config=$(find /usr/lib64 /usr/lib -name tclConfig.sh -print 2>/dev/null | head -n 1)
test -n "$tcl_config"
cd "$build_dir/src"
CC=clang LD=ld.lld CFLAGS='-O2 -std=gnu11' LDFLAGS=-fuse-ld=lld \
    ./configure --prefix=/opt/redis-test-tcl \
    --with-tcl="$(dirname "$tcl_config")" --with-openssl-dir=/usr \
    --disable-sslv2 --disable-sslv3
make -j"${BUILD_JOBS:-4}"
make install
# Match the actual requirement used by tests/test_helper.tcl.
# shellcheck disable=SC2016
printf 'if {[catch {package require tls 1.6} result]} {puts stderr $result; exit 1}; puts $result\n' |
    TCLLIBPATH=/opt/redis-test-tcl/lib tclsh
