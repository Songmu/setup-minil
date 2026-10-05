# Current specification

## Contract and installation

See [README](../README.md) for supported environments and the public interface.

Installer and maintenance scripts share core-Perl helpers in `scripts/SetupMinil.pm`.
cpm installs the exact Minilla requirement and `runtime/minilla.cpanfile` with
`--with-recommends` and `--top-level-phase=runtime`, including Minilla's runtime
recommendations and default `Module::Build::Tiny` backend. Transitive
recommendations/suggestions are not enabled. cpm handles release lookup and
downloads; there is no allowlist or action-managed release digest verification.
The wrapper records the absolute selected Perl and adds only its local
`lib/perl5`. Only `bin` is exported through `GITHUB_PATH`; `PERL5LIB` is unchanged.

## Tool Cache

Entries use `$RUNNER_TOOL_CACHE/minil/<version-without-v>/<lowercase-arch>` and a
sibling `.complete` marker. Without that root, use
`RUNNER_TEMP/setup-minil-tool-cache` (falling back to `TMPDIR` or `/tmp`).
Reuse requires the marker, executable wrapper, original script, and matching
`installation-id`: Perl path/version/archname, runner OS/architecture, Minilla
version, resolution mode, snapshot digest, and hashes of cpm, both cpanfiles,
installer, and shared module. Incomplete/mismatched entries are replaced.
Installation is staged beside the destination, checked before/after publication,
and marked complete on success. Temporary work/failed staging are removed.
Each version/architecture slot holds one environment: self-hosted jobs must not
share it concurrently. The action never saves/restores `actions/cache` entries.

## Snapshots and maintenance

Snapshots use `snapshots/<minilla-version>/<os>-<arch>-perl-<perl-version>-<perl-archname>/`,
lowercased with unsafe characters replaced by `_`. Each directory requires
`cpanfile`, `cpanfile.snapshot`, and `environment.json` recording exact environment,
Minilla version, and generator provenance. An exact match is verified; otherwise
the installer warns and resolves dynamically. Snapshot mode bootstraps pinned
Carton from `runtime/cpanfile` in a temporary local-lib with dynamic dependencies.
cpm always runs in isolated work directories, never reading a caller's snapshot.

`scripts/update-snapshots <version>` bootstraps fresh Carmel with selected Perl,
promotes recommendations to requirements, generates/replaces that environment's
snapshot, and validates every candidate directory. The dispatch workflow tests
Ubuntu/macOS snapshots and merges artifacts into a Draft PR, always checking out
and targeting the default branch. `runtime/manifest.json` records cpm's provenance
and digest; Carton's single pin is in `runtime/cpanfile`. `scripts/check-runtime`
checks the cpm digest, exact Carton requirement, and absence of vendored Carton
libraries/bootstrap snapshots. `scripts/update-runtime` refreshes cpm from its
manifest source. Bundled upstream code and third-party notices remain unchanged.

CI shares the MIT integration fixture across Ubuntu/macOS and both resolution
modes: selected Perl for dynamic installs, system Perl for snapshots.
Offline regressions cover Tool Cache, failure cleanup, rejected inputs, and
snapshot generation/validation/installation. See README for test commands.
