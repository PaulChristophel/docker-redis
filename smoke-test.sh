#!/bin/sh
set -eu
# Run the exact scratch filesystem as its final uid. Client/test tools stay
# outside the chroot and never enter the delivered image.
mkdir -p /rootfs/tmp/smoke
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj /CN=localhost -addext subjectAltName=DNS:localhost \
    -keyout /rootfs/tmp/smoke/key.pem -out /rootfs/tmp/smoke/cert.pem
chown -R 999:999 /rootfs/tmp/smoke
chroot --userspec=999:999 /rootfs /usr/local/bin/redis-server \
    /etc/redis/redis.conf --bind 127.0.0.1 --port 0 --tls-port 16380 \
    --tls-cert-file /tmp/smoke/cert.pem --tls-key-file /tmp/smoke/key.pem \
    --tls-auth-clients no --save '' --appendonly no > /tmp/redis-smoke.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT HUP INT TERM
cli() {
    /usr/src/redis/src/redis-cli --tls -h localhost -p 16380 \
        --cacert /rootfs/tmp/smoke/cert.pem --raw "$@"
}
ready=no
for _attempt in $(seq 1 60); do
    if [ "$(cli PING 2>/dev/null || true)" = PONG ]; then ready=yes; break; fi
    if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
    sleep 1
done
if [ "$ready" != yes ]; then cat /tmp/redis-smoke.log >&2; exit 1; fi
test "$(cli SET smoke:core ok)" = OK
test "$(cli GET smoke:core)" = ok
test "$(cli JSON.SET smoke:json '$' '{"ok":true}')" = OK
test "$(cli BF.ADD smoke:bloom item)" = 1
test "$(cli TS.CREATE smoke:ts)" = OK
test "$(cli TS.ADD smoke:ts 1 42)" = 1
test "$(cli FT.CREATE smoke:search ON HASH PREFIX 1 smoke:doc: SCHEMA title TEXT)" = OK
cli MODULE LIST
cli INFO memory | grep 'mem_allocator:jemalloc'
cli SHUTDOWN NOSAVE
wait "$server_pid"
trap - EXIT HUP INT TERM
rm -rf /rootfs/tmp/smoke
rpm --root /rootfs -q openSUSE-release
test -s /rootfs/usr/share/redis/runtime-packages.txt
test ! -e /rootfs/usr/bin/zypper
test ! -e /rootfs/usr/bin/python3
test ! -e /rootfs/usr/local/bin/redis-cli
