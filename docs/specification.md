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
| `version` | `minilla.version` in `runtime/manifest.json` | Exact Minilla release in `vX.Y.Z` or `X.Y.Z` form |

It exposes one output:

| Output | Description |
|---|---|
| `version` | Installed Minilla version, normalized to `vX.Y.Z` |

The Action does not expose cache controls, digest overrides, installation
paths, or dependency-resolution diagnostics.

## Installation

The Action performs one installation step:

1. Resolve the selected Perl executable to an absolute path.
2. Read its exact version and `archname`.
3. Normalize the requested Minilla version.
4. Select an exact dependency snapshot when available.
5. Reuse a matching completed Tool Cache installation when available.
6. Otherwise, generate a cpanfile with an exact Minilla version requirement
   and the direct requirements in `runtime/minilla.cpanfile`, then install it
   with bundled cpm directly into the final Tool Cache directory.
7. Replace the generated `minil` launcher with an isolated wrapper.
8. Verify the wrapper, write the installation's completion marker, and add only the
   installation's `bin` directory to `GITHUB_PATH`.

## Runner Tool Cache

The Action follows the tool/version/architecture directory layout and sibling
completion marker used by `@actions/tool-cache`:

```text
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>/
$RUNNER_TOOL_CACHE/minil/<normalized-minilla-version>/<arch>.complete
```

For example, Minilla `vX.Y.Z` on an `X64` runner uses `minil/X.Y.Z/x64`.
The architecture component is `x64` or `arm64`. Outside a runner, when
`RUNNER_TOOL_CACHE` is unset, the cache falls back to
`RUNNER_TEMP/setup-minil-tool-cache` (or the system temporary directory).

An entry is reused only when its completion marker, wrapper, original script,
and `installation-id` are present and the identity matches the current
installation inputs. The identity records the selected Perl path, version,
`archname`, runner OS and architecture, Minilla version, resolution
mode, snapshot digest, bundled cpm digest, bootstrap cpanfile digest, and
the recommended-dependency cpanfile, installer, and shared-module digests.

An incomplete or mismatched entry is replaced. Switching Perl environments
therefore never reuses an incompatible installation, even at the same Minilla
version. Only one environment is stored in each version/architecture slot.
Self-hosted runners must not share this Tool Cache slot between concurrent
jobs.

Installation uses the final directory directly, so installed modules do not
need to support relocation. The completion marker is written only after a
successful installation and wrapper check. Temporary working files and failed
installations are removed on exit.
The Action does not restore or save `actions/cache` entries.

## Recommended dependencies

`runtime/minilla.cpanfile` declares the recommended modules used by Minilla's
distribution and release commands. This list follows the selected Minilla
release's runtime recommendations and is maintained in the repository.
The Action declares these modules as direct requirements so cpm installs them
without relying on recursive recommendation handling.
It also requires `Module::Build::Tiny`, Minilla's default build backend, so
`minil test` and `minil dist` do not depend on a preinstalled copy.

The generated top-level cpanfile combines the exact Minilla version
requirement with these direct requirements, so cpm installs everything in one
invocation. The Action does not download or extract Minilla metadata itself.

This includes `Software::License`, `Version::Next`, `CPAN::Uploader`, and
Minilla's recommended release-testing modules. Dependencies that these modules
declare as `requires` are resolved normally; their own `recommends` and
Minilla's `suggests` are not recursively enabled.

## Perl isolation

The generated wrapper records the absolute path of the selected Perl and adds
only the installation's `lib/perl5` directory when starting Minilla.

The Action does not set job-wide `PERL5LIB`, so unrelated later steps retain
the caller's existing Perl environment.

## Version selection

When the input is omitted or empty, the Action reads `minilla.version` from
`runtime/manifest.json`. This must be an exact release in `vX.Y.Z` form.
An explicit input takes precedence over the manifest default.

The input accepts exact three-component versions with or without the leading
`v`. cpm resolves the requested Minilla version from CPAN. If the requested
release cannot be found or installed, the Action fails.

The Action does not maintain a release allowlist, download tarballs directly,
or add its own release digest verification. It delegates downloads and
dependency resolution to cpm.

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

`scripts/check-snapshots` checks every candidate directory at this depth,
including directories missing `environment.json`, and requires all three files.

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

Both the Carton bootstrap and Minilla installation run cpm from the invocation's
temporary working directory, so a caller's `cpanfile.snapshot` is not loaded.

## Snapshot runtime

cpm needs `Carton::Snapshot` to read a Carton-format snapshot. Snapshot mode
therefore installs the exact Carton version declared in `runtime/cpanfile`
into the invocation's temporary working directory before installing Minilla.

The Carton distribution version is pinned. Its bootstrap dependencies are
resolved dynamically because a Carton snapshot cannot bootstrap the parser
needed to read itself.

The temporary Carton installation and cpm working files are
removed when the Action exits. An incomplete Minilla installation is also
removed. A completed Minilla installation remains in the Runner Tool Cache.

## Bundled runtime

The repository bundles self-contained cpm in `runtime/cpm`.
`runtime/manifest.json` defines the default Minilla release and records cpm's
source commit and SHA-256 digest, along with the Carton bootstrap requirement.

`scripts/check-runtime` verifies:

- the bundled cpm digest
- the default Minilla version format
- the exact Carton requirement and cpanfile digest
- that no vendored Carton library tree or bootstrap snapshot is committed

`scripts/update-runtime` refreshes bundled cpm and the runtime manifest.

## Snapshot maintenance

`scripts/update-snapshots <version>`:

1. Normalizes the requested Minilla version.
2. Always installs Carmel with bundled cpm into a temporary local-lib using the
   selected Perl, and invokes it with that interpreter rather than reusing a
   Carmel launcher on `PATH`.
3. Generates a cpanfile with the exact Minilla version and the direct
   requirements in `runtime/minilla.cpanfile`, so Carmel includes them in the
   snapshot.
4. Generates a Carton snapshot with the current system Perl.
5. Writes exact environment metadata.
6. Replaces the snapshot for that exact environment.
7. Runs `scripts/check-snapshots`.

`.github/workflows/update-snapshots.yml` runs this process on GitHub-hosted
Ubuntu and macOS runners using each image's system Perl, verifies each
generated snapshot with a real Minilla installation, and opens a Draft PR
containing the merged snapshots when dispatched manually. Manual dispatch always
uses the default branch regardless of the dispatch branch, and uses that same
default branch as the PR base. All jobs use the source commit resolved before
generation.

Omitting the workflow's version input uses `minilla.version` from the checked-out
manifest. The resolved version is passed to snapshot verification and PR creation.

## Dependency updates

`.github/renovate.json5` configures Renovate to update the default Minilla release
in `runtime/manifest.json`, the Carton requirement in `runtime/cpanfile`, and
the bundled cpm tag and commit in `runtime/manifest.json`. The cpm update workflow
refreshes the bundled executable and checksums only when the cpm entry changes.
When a same-repository Renovate PR changes only the default Minilla version and
snapshots for that release, the snapshot workflow generates and verifies Ubuntu
and macOS snapshots from the PR head commit. It commits the merged snapshots to
the same PR branch and dispatches CI. Other runtime changes or unrelated files
are rejected; PRs without a default Minilla version change skip generation.
Snapshots for older releases are retained.

## Development

```sh
make test
make integration
```

`make test` runs runtime, snapshot, and script checks followed by the offline
regression suite with `prove -v t`. You can also run `prove -v t` directly.
`make integration` runs the same checks followed by `t/smoke.sh`, which performs
a real Minilla installation and exercises distribution commands.

Installer and maintenance scripts use the selected Perl's core modules. The
offline regression suite in `t/` shares a cpm fixture; integration checks exercise
the same Minilla distribution fixture locally and in CI.

The shared `scripts/SetupMinil.pm` module exports helpers only when explicitly
requested, for example `use SetupMinil qw(read_file)` or
`perl -I scripts -MSetupMinil=default_version -e 'print default_version()'`.

## Releases

Releases are prepared by tagpr. Merging its release pull request creates a
SemVer tag and GitHub Release, then `.github/workflows/tagpr.yml` moves the
major-version tag (currently `v0`) to the new release.

Users can reference the Action by its moving major-version tag, an exact release
tag, or a full commit SHA. Pinning to a full commit SHA is recommended for
reproducible workflows.

## Continuous integration

CI covers:

- runtime and snapshot structure checks on Ubuntu and macOS
- dynamic installation with a selected Perl on Ubuntu and macOS
- snapshot generation and snapshot-only installation on the GitHub-hosted
  system Perl for Ubuntu and macOS
- snapshot-only installation from committed snapshots without regeneration
  on Ubuntu and macOS, requiring an exact system Perl environment match and
  verifying that the tracked snapshot files remain unchanged
- rejection of invalid version formats
- Tool Cache layout, completion markers, reuse, invalidation, and failed-install
  cleanup
- real `minil test` and `minil dist` invocations against the MIT-licensed fixture
  distribution, including test results and the generated archive
