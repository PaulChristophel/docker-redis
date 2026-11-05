# Contributing

Contributions that improve the PostgreSQL builds, supported extensions,
operating-system variants, documentation, or release automation are welcome.

## Before making a change

Open an issue for changes that alter the supported PostgreSQL versions, image
variants, extension set, or release behavior. Bug fixes and focused
documentation improvements can go directly to a pull request.

Keep changes scoped to this repository's purpose: building PostgreSQL standard
images for CloudNativePG from upstream source. The standard variants omit the
Perl, Python, and Tcl runtimes; support for their untrusted procedural
languages belongs in the corresponding `-untrusted` variants.

## Repository layout

- `images.json` is the source of truth for PostgreSQL releases, source
  checksums, extension revisions, build variants, and release channels.
- `photon.dockerfile`, `fedora.dockerfile`, and `rockylinux.dockerfile` define
  the distribution-specific builds.
- `.github/workflows/release.yml` builds and publishes the complete matrix.
- `scripts/generate_catalogs.py` converts published image digests into
  CloudNativePG `ClusterImageCatalog` manifests.
- `image-catalogs/` contains the generated, digest-pinned catalogs.

When adding or updating downloaded source, pin both its immutable revision and
its SHA-256 checksum. Base images should remain digest-pinned.

## Local validation

Build the affected variant with Podman. The Dockerfiles' defaults are suitable
for a quick validation build:

```sh
/opt/homebrew/bin/podman build \
  --platform linux/amd64 \
  -f photon.dockerfile \
  -t localhost/postgres:standard-photon5 .
```

Use the relevant Dockerfile and tag for Fedora or Rocky Linux changes. To test
an untrusted variant, pass `--build-arg WITH_UNTRUSTED_LANGUAGES=true`.

Every Dockerfile runs PostgreSQL's `check-world` suite during the build and an
image-level smoke test before producing the final image. A successful complete
build is therefore the primary validation for Dockerfile or dependency
changes.

For Python changes, format and compile the script:

```sh
/Users/pmartin47/Library/Python/3.14/bin/black scripts/generate_catalogs.py
PYTHONPYCACHEPREFIX=/tmp/docker-postgresql-pycache \
  /opt/homebrew/bin/python3.14 -m py_compile scripts/generate_catalogs.py
```

Also check configuration syntax and whitespace before submitting:

```sh
/opt/homebrew/bin/python3.14 -m json.tool images.json >/dev/null
/opt/homebrew/bin/git diff --check
```

Do not hand-edit generated catalogs when changing a build. The release workflow
records the registry digests, regenerates the catalogs, and opens the catalog
update pull request after all matrix builds succeed.

## Pull requests

In the pull request description:

- explain the problem and the intended behavior;
- identify the PostgreSQL versions and OS variants affected;
- list the validation commands run and their results; and
- call out anything that could not be tested locally.

Keep unrelated changes in separate pull requests. A pull request that changes
the common image contract should update every affected distribution rather
than leaving variants with different PostgreSQL features unintentionally.

By contributing, you agree that your contribution is licensed under the terms
of this repository's [LICENSE](LICENSE).
