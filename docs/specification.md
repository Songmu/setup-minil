# Current specification

This document describes the current behavior of `setup-minil`.

[日本語版](specification.ja.md)

## Supported environment

- GitHub Actions runners using Linux or macOS
- Runner architectures reported as `X64` or `ARM64`
- Perl 5.24 or later
- A Perl executable selected on `PATH` before the action runs

Windows is not supported.

## Public interface

The composite Action accepts one input:

| Input | Default | Description |
|---|---|---|
| `version` | `v3.2.0` | Exact Minilla release listed in `manifests/minilla.json` |

It exposes one output:

| Output | Description |
|---|---|
| `version` | Installed Minilla version |

The Action does not expose cache controls, digest overrides, installation
paths, or dependency-resolution diagnostics.

## Installation

The Action performs one installation step:

1. Resolve the selected Perl executable to an absolute path.
2. Read its exact version and `archname`.
3. Validate the requested Minilla version against `manifests/minilla.json`.
4. Select an exact dependency snapshot when available.
5. Reuse a matching completed Tool Cache installation, or download the Minilla
   release over HTTPS.
6. Verify the tarball against the SHA-256 digest in the manifest.
7. Install Minilla and its dependencies with bundled cpm into a staging
   directory in the Runner Tool Cache.
8. Replace the generated `minil` launcher with an isolated wrapper.
9. Publish the installation, write its completion marker, and add only the
   installation's `bin` directory to `GITHUB_PATH`.

## Runner Tool Cache

The Action follows the tool/version/architecture directory layout and sibling
completion marker used by `@actions/tool-cache`:

```text
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>/
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>.complete
```

For example, Minilla `v3.2.0` on an `X64` runner uses `minil/3.2.0/x64`.
The architecture component is `x64` or `arm64`. Outside a runner, when
`RUNNER_TOOL_CACHE` is unset, the cache falls back to
`RUNNER_TEMP/setup-minil-tool-cache` (or the system temporary directory).

An entry is reused only when its completion marker, wrapper, original script,
and `installation-id` are present and the identity matches the current
installation inputs. The identity records the selected Perl path, version,
`archname`, runner OS and architecture, Minilla tarball digest, resolution
mode, snapshot digest, bundled cpm digest, bootstrap cpanfile digest, and
installer digest.

An incomplete or mismatched entry is replaced. Switching Perl environments
therefore never reuses an incompatible installation, even at the same Minilla
version. Only one environment is stored in each version/architecture slot.
Self-hosted runners must not share this Tool Cache slot between concurrent
jobs.

Installation is staged beside the final directory and the completion marker
is written only after a successful installation and wrapper check.
Temporary working files and failed staging directories are removed on exit.
The Action does not restore or save `actions/cache` entries.

## Perl isolation

The generated wrapper records the absolute path of the selected Perl and adds
only the installation's `lib/perl5` directory when starting Minilla.

The Action does not set job-wide `PERL5LIB`, so unrelated later steps retain
the caller's existing Perl environment.

## Release integrity

Supported releases are allowlisted in `manifests/minilla.json`. Each entry
provides the release URL and expected SHA-256 digest.

The Action does not accept a caller-supplied digest. A requested release must
match the repository manifest, and every downloaded tarball must match its
committed digest.

## Dependency snapshots

Snapshot lookup uses this directory format:

```text
snapshots/<minilla-version>/<os>-<runner-arch>-perl-<perl-version>-<perl-archname>/
```

Every path component is lowercased, and characters outside
`A-Z`, `a-z`, `0-9`, `_`, `.`, and `-` are replaced with `_`.

Each snapshot directory contains:

- `cpanfile`
- `cpanfile.snapshot`
- `environment.json`

`environment.json` records:

- runner OS
- runner architecture
- exact Perl version
- exact Perl `archname`
- Minilla version
- snapshot generator metadata

The Action derives the path directly from the current environment and verifies
the metadata before using the snapshot. There is no separate snapshot index.

If no exact directory exists, the Action emits a warning and lets cpm resolve
dependencies dynamically from CPAN.

## Snapshot runtime

cpm needs `Carton::Snapshot` to read a Carton-format snapshot. Snapshot mode
therefore installs the exact Carton version declared in `runtime/cpanfile`
into the invocation's temporary working directory before installing Minilla.

The Carton distribution version is pinned. Its bootstrap dependencies are
resolved dynamically because a Carton snapshot cannot bootstrap the parser
needed to read itself.

The temporary Carton installation, downloads, and cpm working files are
removed when the Action exits. An incomplete Minilla staging directory is also
removed. A completed Minilla installation remains in the Runner Tool Cache.

## Bundled runtime

The repository bundles self-contained cpm in `runtime/cpm`.
`runtime/manifest.json` records its source commit and SHA-256 digest, along
with the Carton bootstrap requirement.

`scripts/check-runtime` verifies:

- the bundled cpm digest
- the exact Carton requirement and cpanfile digest
- that no vendored Carton library tree or bootstrap snapshot is committed

`scripts/update-runtime` refreshes bundled cpm and the runtime manifest.

## Snapshot maintenance

`scripts/update-snapshots <version>`:

1. Validates the requested Minilla version.
2. Installs Carmel with bundled cpm when Carmel is not already available.
3. Generates a Carton snapshot with the current system Perl.
4. Writes exact environment metadata.
5. Replaces the snapshot for that exact environment.
6. Runs `scripts/check-snapshots`.

`.github/workflows/update-snapshots.yml` runs this process on GitHub-hosted
Ubuntu and macOS runners using each image's system Perl, verifies each
generated snapshot with a real Minilla installation, and opens a Draft PR
containing the merged snapshots.

## Continuous integration

CI covers:

- runtime and snapshot structure checks on Ubuntu and macOS
- dynamic installation with a selected Perl on Ubuntu and macOS
- snapshot generation and snapshot-only installation on the GitHub-hosted
  system Perl for Ubuntu and macOS
- rejection of unsupported Minilla versions
- Tool Cache layout, completion markers, reuse, invalidation, and failed-install
  cleanup
- a real `minil test` invocation against the fixture distribution
