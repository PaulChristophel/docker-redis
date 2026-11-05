#!/bin/sh
set -eu
mkdir -p /rootfs/usr/local/bin /rootfs/usr/local/lib/redis/modules \
    /rootfs/etc/redis /rootfs/data /rootfs/tmp
install -m 0755 src/redis-server src/redis-cli /rootfs/usr/local/bin/
for module in redisbloom/redisbloom redisearch/redisearch redisjson/rejson redistimeseries/redistimeseries; do
    install -m 0755 "modules/${module}.so" /rootfs/usr/local/lib/redis/modules/
done
strip --strip-unneeded /rootfs/usr/local/bin/redis-server /rootfs/usr/local/bin/redis-cli /rootfs/usr/local/lib/redis/modules/*.so

# Identify package owners of the complete ELF dependency closure. Zypper, not
# this script, installs the runtime libraries and their package dependencies.
: > /tmp/runtime-libraries
for binary in /rootfs/usr/local/bin/redis-server /rootfs/usr/local/bin/redis-cli /rootfs/usr/local/lib/redis/modules/*.so; do
    ldd "${binary}" > /tmp/ldd-output
    if grep -q 'not found' /tmp/ldd-output; then
        cat /tmp/ldd-output >&2
        exit 1
    fi
    awk '/=> \/.* \(/ {print $3} /^\s*\/.* \(/ {print $1}' /tmp/ldd-output >> /tmp/runtime-libraries
done
: > /tmp/runtime-package-names
sort -u /tmp/runtime-libraries | while IFS= read -r library; do
    test -f "${library}"
    rpm -qf "$(readlink -f "${library}")" --qf '%{NAME}\n' >> /tmp/runtime-package-names
done
sort -u /tmp/runtime-package-names > /tmp/runtime-package-names.sorted
set -- openSUSE-release
while IFS= read -r package; do
    set -- "$@" "$package"
done < /tmp/runtime-package-names.sorted
zypper --installroot /rootfs --non-interactive --gpg-auto-import-keys \
    install --no-recommends "$@"
zypper --installroot /rootfs --non-interactive clean --all
rm -rf /rootfs/var/cache/zypp
rpm --root /rootfs -q openSUSE-release
test -s /rootfs/usr/lib/os-release
mkdir -p /rootfs/usr/share/redis
rpm --root /rootfs -qa --qf '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n' |
    sort > /rootfs/usr/share/redis/runtime-packages.txt

# Check the actual installed loader/library set before starting Redis.
interpreter=$(readelf -l /rootfs/usr/local/bin/redis-server |
    sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p')
test -n "$interpreter"
chroot /rootfs "$interpreter" --list /usr/local/bin/redis-server
chroot /rootfs "$interpreter" --list /usr/local/bin/redis-cli
for module in /rootfs/usr/local/lib/redis/modules/*.so; do
    chroot /rootfs "$interpreter" --list "${module#/rootfs}"
done
install -m 0644 /opt/build/redis.conf /rootfs/etc/redis/redis.conf
for project in . modules/redisbloom/src modules/redisearch/src modules/redisjson/src modules/redistimeseries/src; do
    case "$project" in .) name=redis ;; *) name=$(basename "$(dirname "$project")") ;; esac
    mkdir -p "/rootfs/usr/share/licenses/${name}"
    for license in "$project"/LICENSE* "$project"/COPYING* "$project"/RSAL* "$project"/SSPL* "$project"/AGPL*; do
        if [ -f "$license" ]; then cp "$license" "/rootfs/usr/share/licenses/${name}/"; fi
    done
done
if awk -F: '$1 == "redis" || $3 == 999 {found=1} END {exit !found}' /rootfs/etc/passwd; then
    echo 'Redis name or uid 999 already exists in runtime rootfs' >&2
    exit 1
fi
if awk -F: '$1 == "redis" || $3 == 999 {found=1} END {exit !found}' /rootfs/etc/group; then
    echo 'Redis group name or gid 999 already exists in runtime rootfs' >&2
    exit 1
fi
printf 'redis:x:999:999:Redis:/data:/sbin/nologin\n' >> /rootfs/etc/passwd
printf 'redis:x:999:\n' >> /rootfs/etc/group
chmod 1777 /rootfs/tmp
chown 999:999 /rootfs/data
find /rootfs -type f -print | sort
