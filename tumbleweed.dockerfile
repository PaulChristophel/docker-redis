# Build from images.json with: ./scripts/build-image.sh
ARG BASE=docker.io/opensuse/tumbleweed:latest@sha256:24631e8a662ce93a4dc6d612f0f4b6d334606d624b157e3f161957de68ce2876
FROM ${BASE} AS build-dependencies
ARG REDIS_VERSION=8.10.3
ARG REDIS_SHA256=5e0c00ed77f789fb1a4a30f1fbb58a793cc88c41c0f11f0e38e1b4f192991188
ARG BUILD_JOBS=4

RUN zypper --non-interactive --gpg-auto-import-keys install --no-recommends \
      make gcc gcc-c++ glibc-devel binutils cmake git curl tar gzip xz unzip \
      rsync patch autoconf automake libtool pkgconf-pkg-config \
      libopenssl-devel openssl ca-certificates rust cargo \
      python3 python3-devel python3-pip python3-virtualenv python313-packaging \
      which findutils gawk tcl \
 && llvm_major="$(rustc -vV | sed -n 's/^LLVM version: \([0-9]*\).*/\1/p')" \
 && test -n "${llvm_major}" \
 && zypper --non-interactive --gpg-auto-import-keys install --no-recommends \
      "clang${llvm_major}" "lld${llvm_major}" "llvm${llvm_major}" \
 && mkdir -p /opt/llvm-tools/bin \
 && for tool in clang clang++ llvm-ar llvm-ranlib llvm-nm; do \
      tool_path="$(command -v "${tool}-${llvm_major}" || command -v "${tool}")"; \
      test -n "${tool_path}"; \
      ln -s "${tool_path}" "/opt/llvm-tools/bin/${tool}"; \
    done \
 && for pair in ar:llvm-ar ranlib:llvm-ranlib nm:llvm-nm; do \
      ln -s "${pair#*:}" "/opt/llvm-tools/bin/${pair%:*}"; \
    done \
 && clang_major="$(/opt/llvm-tools/bin/clang --version | sed -n '1s/.*version \([0-9]*\).*/\1/p')" \
 && test "${clang_major}" = "${llvm_major}" \
 && ld.lld --version | grep -E "LLD ${llvm_major}\." \
 && python3 -m virtualenv /opt/build-venv \
 && zypper --non-interactive clean --all

RUN llvm_major="$(rustc -vV | sed -n 's/^LLVM version: \([0-9]*\).*/\1/p')" \
 && zypper --non-interactive --gpg-auto-import-keys install --no-recommends \
      bash coreutils grep sed diffutils procps jq wget bzip2 \
      libffi-devel libxcrypt-devel zlib-ng-compat-devel libdispatch-devel tcl-devel "clang${llvm_major}-devel"
ENV PATH=/opt/build-venv/bin:/opt/llvm-tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm LD=ld.lld
ENV CFLAGS=-O3 CXXFLAGS=-O3
ENV CPATH=/usr/include/block
ENV VIRTUAL_ENV=/opt/build-venv
ENV TCLLIBPATH=/opt/redis-test-tcl/lib
ARG TCLTLS_VERSION=1.7.22
ARG TCLTLS_SHA256=e84e2b7a275ec82c4aaa9d1b1f9786dbe4358c815e917539ffe7f667ff4bc3b4
COPY install-test-tcltls.sh /opt/build/install-test-tcltls.sh
RUN TCLTLS_VERSION="${TCLTLS_VERSION}" TCLTLS_SHA256="${TCLTLS_SHA256}" \
      BUILD_JOBS="${BUILD_JOBS}" sh /opt/build/install-test-tcltls.sh
COPY check-build-deps.sh /opt/build/check-build-deps.sh
RUN sh /opt/build/check-build-deps.sh

FROM build-dependencies AS builder
ARG REDIS_VERSION=8.10.3
ARG REDIS_SHA256=5e0c00ed77f789fb1a4a30f1fbb58a793cc88c41c0f11f0e38e1b4f192991188
ARG BUILD_JOBS=4
WORKDIR /usr/src/redis
RUN curl --fail --location --retry 3 \
      "https://github.com/redis/redis/releases/download/${REDIS_VERSION}/redis-full.tar.gz" \
      -o /tmp/redis.tar.gz \
 && echo "${REDIS_SHA256}  /tmp/redis.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/redis.tar.gz --strip-components=1 \
 && rm /tmp/redis.tar.gz

COPY build.sh assemble-rootfs.sh smoke-test.sh /opt/build/
COPY redis.conf /opt/build/redis.conf
RUN BUILD_JOBS="${BUILD_JOBS}" sh /opt/build/build.sh
RUN sh /opt/build/assemble-rootfs.sh
RUN sh /opt/build/smoke-test.sh

FROM scratch
ARG BASE
ARG REDIS_VERSION=8.10.3
ARG IMAGE_AUTHORS="Paul Christophel <pmartin@gatech.edu>"
ARG IMAGE_REPOSITORY=docker.io/pcm0/redis
ARG IMAGE_REVISION=unknown
ARG IMAGE_CREATED=1970-01-01T00:00:00Z
LABEL org.opencontainers.image.title="Redis with TLS and bundled modules on openSUSE Tumbleweed" \
      org.opencontainers.image.description="Redis server, Search, JSON, Bloom, TimeSeries, and required runtime libraries only." \
      org.opencontainers.image.authors="${IMAGE_AUTHORS}" \
      org.opencontainers.image.version="${REDIS_VERSION}" \
      org.opencontainers.image.ref.name="${IMAGE_REPOSITORY}" \
      org.opencontainers.image.base.name="${BASE}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}"
COPY --from=builder /rootfs/ /
USER 999:999
WORKDIR /data
EXPOSE 6379 6380
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/redis-server"]
CMD ["/etc/redis/redis.conf"]
