#!/usr/bin/env bash

set -euo pipefail

pushd "$(cd "$(dirname "$0")" && pwd)"

BASE=docker.io/photon:5.0@sha256:3d7e9a35fd55277a056d9e1c54841e6b862a8df7e0caa56fa9c0453969f5329d
PG_MAJOR=18
PG_VERSION=18.6
PG_SHA256=555610c24d53e4316da5b7d3fc25c279d96856d5e0e23ee308c328c5fa881d9f
POSTGRES_CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3"
POSTGRES_LDFLAGS="-Wl,-z,relro,-z,now -Wl,--as-needed"
PG_CRON_VERSION=1.6.8
PG_CRON_COMMIT=5cedfa472ccc83567aa23ec645925ed8489a7797
PG_CRON_SOURCE_SHA256=cba185da9308d2c624ded35a596937ce391badd60665ab6badc55bd8e78a1e94
PGVECTOR_VERSION=0.8.7
PGVECTOR_COMMIT=f37c13f68b57d2c3472b2214fbcff699d6d34876
PGVECTOR_SOURCE_SHA256=83d673c3b287cddbf3879f86215f043f2c2b56c69d37b2a77504910db1ed6e56
PGAUDIT_VERSION=18.0
PGAUDIT_COMMIT=f39f8dbb15dc5bd4cbe5f1e5abe0d930ed7593a8
PGAUDIT_SOURCE_SHA256=bbfc57be090c82b4efd8f8ed7f613e2d8537c38c35f25bb2d1c005d5747ef2e4
TAG="${PG_MAJOR}-standard-photon5"
IMAGE_TITLE="CloudNativePG PostgreSQL on Photon"
IMAGE_DESCRIPTION="PostgreSQL built from upstream source on Photon OS for CloudNativePG."
IMAGE_AUTHORS="Paul Christophel <pmartin@gatech.edu>"
IMAGE_VENDOR="Paul Christophel"
IMAGE_SOURCE="https://github.com/PaulChristophel/docker-postgresql"
IMAGE_REPOSITORY="docker.io/pcm0/postgres"
IMAGE_URL="https://hub.docker.com/r/pcm0/postgres"
IMAGE_DOCUMENTATION="https://github.com/PaulChristophel/docker-postgresql#readme"
IMAGE_REVISION="$(git rev-parse HEAD)"
IMAGE_CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
IMAGE_LICENSES="AGPL-3.0-or-later"

podman build \
    --build-arg BASE="${BASE}" \
    --build-arg PG_MAJOR="${PG_MAJOR}" \
    --build-arg PG_VERSION="${PG_VERSION}" \
    --build-arg PG_SHA256="${PG_SHA256}" \
    --build-arg POSTGRES_CFLAGS="${POSTGRES_CFLAGS}" \
    --build-arg POSTGRES_LDFLAGS="${POSTGRES_LDFLAGS}" \
    --build-arg PG_CRON_VERSION="${PG_CRON_VERSION}" \
    --build-arg PG_CRON_COMMIT="${PG_CRON_COMMIT}" \
    --build-arg PG_CRON_SOURCE_SHA256="${PG_CRON_SOURCE_SHA256}" \
    --build-arg PGVECTOR_VERSION="${PGVECTOR_VERSION}" \
    --build-arg PGVECTOR_COMMIT="${PGVECTOR_COMMIT}" \
    --build-arg PGVECTOR_SOURCE_SHA256="${PGVECTOR_SOURCE_SHA256}" \
    --build-arg PGAUDIT_VERSION="${PGAUDIT_VERSION}" \
    --build-arg PGAUDIT_COMMIT="${PGAUDIT_COMMIT}" \
    --build-arg PGAUDIT_SOURCE_SHA256="${PGAUDIT_SOURCE_SHA256}" \
    --build-arg IMAGE_TITLE="${IMAGE_TITLE}" \
    --build-arg IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION}" \
    --build-arg IMAGE_AUTHORS="${IMAGE_AUTHORS}" \
    --build-arg IMAGE_VENDOR="${IMAGE_VENDOR}" \
    --build-arg IMAGE_OWNER="${IMAGE_OWNER}" \
    --build-arg IMAGE_SOURCE="${IMAGE_SOURCE}" \
    --build-arg IMAGE_REPOSITORY="${IMAGE_REPOSITORY}:${TAG}" \
    --build-arg IMAGE_URL="${IMAGE_URL}" \
    --build-arg IMAGE_DOCUMENTATION="${IMAGE_DOCUMENTATION}" \
    --build-arg IMAGE_REVISION="${IMAGE_REVISION}" \
    --build-arg IMAGE_CREATED="${IMAGE_CREATED}" \
    --build-arg IMAGE_LICENSES="${IMAGE_LICENSES}" \
    --build-arg IMAGE_DISTRIBUTION=photon \
    --build-arg IMAGE_DISTRIBUTION_VERSION=5.0 \
    --annotation "org.opencontainers.image.title=${IMAGE_TITLE}" \
    --annotation "org.opencontainers.image.description=${IMAGE_DESCRIPTION}" \
    --annotation "org.opencontainers.image.authors=${IMAGE_AUTHORS}" \
    --annotation "org.opencontainers.image.vendor=${IMAGE_VENDOR}" \
    --annotation "org.opencontainers.image.source=${IMAGE_SOURCE}" \
    --annotation "org.opencontainers.image.url=${IMAGE_URL}" \
    --annotation "org.opencontainers.image.documentation=${IMAGE_DOCUMENTATION}" \
    --annotation "org.opencontainers.image.revision=${IMAGE_REVISION}" \
    --annotation "org.opencontainers.image.created=${IMAGE_CREATED}" \
    --annotation "org.opencontainers.image.licenses=${IMAGE_LICENSES}" \
    --annotation "org.opencontainers.image.base.name=${BASE}" \
    --annotation "org.opencontainers.image.version=${PG_VERSION}" \
    --annotation "org.opencontainers.image.ref.name=${IMAGE_REPOSITORY}:${TAG}" \
    --annotation "org.opencontainers.image.component.postgresql.version=${PG_VERSION}" \
    --annotation "org.opencontainers.image.component.pg_cron.version=${PG_CRON_VERSION}" \
    --annotation "org.opencontainers.image.component.pg_cron.revision=${PG_CRON_COMMIT}" \
    --annotation "org.opencontainers.image.component.pgvector.version=${PGVECTOR_VERSION}" \
    --annotation "org.opencontainers.image.component.pgvector.revision=${PGVECTOR_COMMIT}" \
    --annotation "org.opencontainers.image.component.pgaudit.version=${PGAUDIT_VERSION}" \
    --annotation "org.opencontainers.image.component.pgaudit.revision=${PGAUDIT_COMMIT}" \
    --annotation "org.opencontainers.image.component.python.version=not-installed" \
    --annotation "org.opencontainers.image.component.perl.version=not-installed" \
    --annotation "org.opencontainers.image.component.tcl.version=not-installed" \
    --annotation "edu.gatech.image.variant.trust=trusted" \
    --annotation "edu.gatech.image.untrusted-languages=false" \
    --annotation "edu.gatech.image.os.distribution=photon" \
    --annotation "edu.gatech.image.os.version=5.0" \
    --platform=linux/amd64 \
    -f photon.dockerfile \
    -t "${IMAGE_REPOSITORY}:${TAG}"

podman push "${IMAGE_REPOSITORY}:${TAG}"
popd
