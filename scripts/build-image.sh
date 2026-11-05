#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="${repo_dir}/images.json"
dry_run=false
if [[ "${1:-}" == --dry-run ]]; then
    dry_run=true
    shift
fi
if [[ "${1:-}" == --help ]]; then
    printf '%s\n' 'Usage: scripts/build-image.sh [--dry-run] [podman build options...]' \
        'Optional environment: PODMAN, REDIS_VERSION, VARIANT, BUILD_JOBS.'
    exit 0
fi
release=$(jq -ce --arg version "${REDIS_VERSION:-}" '
    if $version == "" then .redis[0]
    else [.redis[] | select(.version == $version)] | select(length == 1) | .[0]
    end | select(. != null)' "$manifest")
variant=$(jq -ce --arg tag "${VARIANT:-}" '
    if $tag == "" then .variants[0]
    else [.variants[] | select(.tag == $tag)] | select(length == 1) | .[0]
    end | select(. != null)' "$manifest")
version=$(jq -er '.version' <<< "$release")
checksum=$(jq -er '.sha256 | select(test("^[0-9a-f]{64}$"))' <<< "$release")
variant_tag=$(jq -er '.tag' <<< "$variant")
dockerfile=$(jq -er '.dockerfile' <<< "$variant")
os=$(jq -er '.os' <<< "$variant")
base=$(jq -er --arg os "$os" '.distributions[$os].base' "$manifest")
platform=$(jq -er '.platform' "$manifest")
image=$(jq -er '.image' "$manifest")
jobs=${BUILD_JOBS:-$(jq -er '.defaults.build_jobs' "$manifest")}
tcltls_version=$(jq -er '.defaults.tcltls_version' "$manifest")
tcltls_checksum=$(jq -er '.defaults.tcltls_sha256 | select(test("^[0-9a-f]{64}$"))' "$manifest")
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo 'BUILD_JOBS must be a positive integer' >&2; exit 1; }
test -f "${repo_dir}/${dockerfile}"
command=("${PODMAN:-podman}" build "--platform=${platform}"
    -f "${repo_dir}/${dockerfile}"
    --build-arg "BASE=${base}"
    --build-arg "REDIS_VERSION=${version}"
    --build-arg "REDIS_SHA256=${checksum}"
    --build-arg "BUILD_JOBS=${jobs}"
    --build-arg "TCLTLS_VERSION=${tcltls_version}"
    --build-arg "TCLTLS_SHA256=${tcltls_checksum}"
    --build-arg "IMAGE_REPOSITORY=${image}"
    --build-arg "IMAGE_REVISION=$(git -C "$repo_dir" rev-parse --verify HEAD 2>/dev/null || printf unknown)"
    --build-arg "IMAGE_CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    -t "${image}:${version}-${variant_tag}"
    "$@" "$repo_dir")
if "$dry_run"; then
    printf '%q ' "${command[@]}"
    printf '\n'
else
    exec "${command[@]}"
fi
