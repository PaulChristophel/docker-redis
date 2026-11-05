# Redis source image for Podman

Redis 8.10.3 with jemalloc, Clang/LLVM LTO, TLS, Search, JSON, Bloom, and
TimeSeries. The final `scratch` image contains `redis-server`, the four module
libraries, their package-managed runtime dependencies, configuration, licenses,
and writable `/data` and `/tmp` directories. `zypper --installroot` installs the
packages owning the ELF dependencies plus `openSUSE-release`, with recommendations
disabled. OS identity files and the runtime RPM database are retained for scanners.
Required OS dependencies can include Bash and BusyBox; the image does not contain
zypper, compilers, Python, or `redis-cli`. Individual library files are not copied.

## Build

Run from the repository root. The helper reads the image name, platform, source
version/checksum, build concurrency, and selected base from `images.json`:

```sh
PODMAN=/opt/homebrew/bin/podman ./scripts/build-image.sh
```

On Linux, run `./scripts/build-image.sh` with Podman and jq on PATH. The manifest
selects `linux/amd64`; Podman handles emulation when building on an ARM Mac.
Inspect the command without building with `./scripts/build-image.sh --dry-run`.
Select entries using `REDIS_VERSION` and `VARIANT`, and override parallelism
with `BUILD_JOBS`. Additional arguments are passed to `podman build`.

`images.json` is the source of truth for local builds and the release workflow.
The active variant uses `tumbleweed.dockerfile`; the Redis full-source archive
is SHA-256 checked. Module builds download additional dependencies. Tumbleweed
RPM repositories are rolling: a pinned base does not freeze subsequently
installed packages. Direct `podman build -f tumbleweed.dockerfile .` is also
possible, but uses Dockerfile defaults instead of reading the manifest.

The builder selects Clang/LLVM matching the installed Rust compiler's LLVM major.
LLVM `nm`, `ar`, and `ranlib` are also exposed under their conventional names on
PATH, for nested build scripts that do not honor the corresponding variables.
No jemalloc source patch or symbol-renaming compiler defines are applied. The
single core build uses the upstream jemalloc configuration and verifies its five
Redis extension symbols before building the modules separately. Configure detects the target platform; no CPU-specific
compiler flags or fixed page-size overrides are added. Redis and jemalloc use
`-O3 -flto`; RediSearch's CMake RelWithDebInfo optimization is explicitly `-O3`.
On an ARM Mac, the amd64 build requires Podman's x86-64 emulation support and
will generally take longer than a native build.

The `build-dependencies` stage validates all required commands, Python/Tcl TLS,
OpenSSL/libcrypt, OpenMP, and BlocksRuntime C/C++ linking, libclang loading, and Rust/C
LTO link before compiling Redis or its modules. Explicit development dependencies
include `clang<LLVM-major>-devel`, `libdispatch-devel`, `libffi-devel`, `libxcrypt-devel`, and the
Tumbleweed `zlib-ng-compat-devel` provider.

Build gates include upstream `make -C src test`, `./runtest --tls`, and a smoke
test of the exact scratch filesystem as uid/gid 999. The smoke test connects over
TLS and exercises each of the four modules. These are not the four modules'
complete upstream test suites. The build fails if any required gate fails.

## Run with TLS

Supply a certificate/key signed by your CA and client certificates. The sample
TLS configuration requires client certificates. The private key must be readable
by container uid 999. Neither certificates nor private keys are baked into the image.

```sh
/opt/homebrew/bin/podman volume create redis-data
/opt/homebrew/bin/podman run --rm --name redis \
  --cap-drop=all --security-opt=no-new-privileges \
  --read-only --tmpfs /tmp:rw,nosuid,nodev,noexec,size=64m \
  -p 127.0.0.1:6380:6380 \
  -v redis-data:/data \
  -v "$PWD/redis-tls.conf:/etc/redis/tls.conf:ro" \
  -v "$PWD/tls:/tls:ro" \
  docker.io/pcm0/redis:8.10.3-tumbleweed /etc/redis/tls.conf
```

Configure Redis ACLs separately if you need application-level authentication or
authorization. For Linux hosts with SELinux, add appropriate volume labels.
By default the image loads all four modules, enables AOF persistence, and runs
as uid/gid 999. Its default configuration uses port 6379 with protected mode;
the TLS example disables that plaintext port. Mount a custom configuration or
append Redis command-line options to change behavior. Keep the four `loadmodule`
directives in custom configurations if you want all modules loaded.

`redis-cli` is intentionally builder-only. Use an external client for operational
checks. Redis receives SIGTERM directly as PID 1 and handles graceful shutdown.

## Inspect

```sh
/opt/homebrew/bin/podman run --rm docker.io/pcm0/redis:8.10.3-tumbleweed --version
/opt/homebrew/bin/podman image inspect docker.io/pcm0/redis:8.10.3-tumbleweed \
  --format '{{.Size}}'
```

## Release workflow

The release workflow expands the Redis releases and variants from `images.json`,
builds and tests each image for the configured platform, then publishes it with
Podman using the repository's `DOCKERHUB_TOKEN` secret. Tags are
`<version>-<variant>`. It also creates a provenance attestation. The inherited
PostgreSQL catalog generation is no longer part of this workflow.

## Runtime package inventory

`/usr/share/redis/runtime-packages.txt` lists every installed runtime RPM and its
version/architecture. It is generated from the final rootfs RPM database, including
`openSUSE-release` and dependency packages pulled in by zypper. The list depends on
the libraries linked by the four module builds; it excludes the build-stage RPMs.

To inspect it without requiring a shell in the image:

```sh
container=$(podman create docker.io/pcm0/redis:8.10.3-tumbleweed)
podman cp "$container:/usr/share/redis/runtime-packages.txt" ./runtime-packages.txt
podman rm "$container"
```

The Blocks header is supplied by `libdispatch-devel` at `/usr/include/block/Block.h`.
`CPATH=/usr/include/block` makes it visible to nested Clang builds. RedisBloom
is built with Readies `CC_FLAGS.opt=-O3 -flto -fblocks` and
`LD_LIBS.ext=BlocksRuntime`; these flags are scoped to that module. TimeSeries receives the same Blocks
compile flags with `LD_LIBS.ext=ssl crypto BlocksRuntime` to preserve its TLS
libraries. Runtime
Blocks libraries are selected automatically by the ELF/RPM dependency scan.
RediSearch still prints its unsupported-openSUSE warning: its upstream package
checker does not recognize Tumbleweed, so the build uses the independently
checked toolchain with `IGNORE_MISSING_DEPS=1`.

Autoconf/libtool builds use `LD=ld.lld` (the ELF linker). Only RediSearch
receives `LD=lld`, because its build script validates that driver name and
selects it through Clang's `-fuse-ld=lld` option.

RedisBloom and TimeSeries also receive
`LD_FLAGS.linux=-flto -fuse-ld=lld`. Readies uses `LD_FLAGS` in the final
compiler-driver link, independently of Autoconf's `LD` and conventional
`LDFLAGS`; this ensures their LLVM bitcode objects are linked with lld.
