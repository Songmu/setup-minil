# setup-minil

`setup-minil` is a composite GitHub Action that installs an allowlisted
[Minilla](https://metacpan.org/dist/Minilla) release with the Perl currently
selected on the runner.

The installation is isolated in the Runner Tool Cache. The action adds only
the installed `bin` directory to `PATH`; it does not set job-wide `PERL5LIB` or
modify the caller's local::lib environment.

## Usage

Select Perl before running this action:

```yaml
steps:
  - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262

  - uses: shogo82148/actions-setup-perl@8b574cdc2dffdae49f803204a4f2b716a2fa1db7
    with:
      perl-version: "5.40"

  - uses: Songmu/setup-minil@<full-commit-sha>

  - run: minil --version
```

Pinning this action to a full commit SHA is recommended.

## Inputs

| Input | Default | Description |
|---|---|---|
| `version` | `v3.2.0` | Exact allowlisted Minilla release |
| `expected-sha256` | unset | Optional second assertion for the release tarball digest |
| `cache` | `"false"` | Enable persistent caching when an exact dependency snapshot exists |

`expected-sha256` does not override the repository manifest. When supplied, it
must exactly match the digest committed in `manifests/minilla.json`.

## Outputs

| Output | Description |
|---|---|
| `version` | Installed Minilla version |
| `sha256` | Verified release tarball SHA-256 |
| `perl-path` | Absolute path to the selected Perl |
| `cache-path` | Runner Tool Cache installation directory |
| `cache-hit` | Whether a valid persistent cache entry was restored |
| `tool-cache-hit` | Whether a valid existing Runner Tool Cache entry was reused |
| `resolution-mode` | `snapshot` or `dynamic` |

## Supported Minilla versions

| Version | SHA-256 |
|---|---|
| `v3.2.0` | `c90ea9ead89b595c582d5b569735c349e82d3378b310d35386ff336d3d5ae922` |

Only releases listed in `manifests/minilla.json` can be installed.

## Dependency resolution

The action fingerprints the runner OS, architecture, exact Perl version, and
Perl `archname`.

- If `snapshots/index.json` contains an exact match, bundled cpm runs with the
  snapshot-only resolver.
- Otherwise, the action emits a warning and uses cpm's default resolver.

Snapshot mode first installs the exact Carton version declared in
`runtime/cpanfile` into an isolated temporary local-lib. Carton's transitive
bootstrap dependencies are dynamically resolved.

Dynamic resolution verifies the Minilla release itself but does not fully pin
its transitive dependencies.

## Caching

Persistent caching is available only in snapshot mode. Cache restores use an
exact key and no prefix restore keys. Restored content is validated against
the current Perl fingerprint, Minilla digest, resolution mode, snapshot
digest, wrapper, real script, and Tool Cache completion marker.

An invalid restore is treated as a miss and is not saved again under the same
immutable key. Dynamic installations can still be reused from the Runner Tool
Cache within a job or a suitably isolated self-hosted runner.

Self-hosted runners must not share one `RUNNER_TOOL_CACHE` between concurrent
or differently configured Perl environments.

## Perl selection

cpm v1 requires Perl 5.24 or later. The generated `minil` wrapper records the
absolute selected Perl path and adds the isolated library tree only for the
Minilla process.

Minilla may pass its own include paths to child Perl processes used by commands
such as `minil test`. The isolation guarantee is that this action does not
export `PERL5LIB` to unrelated later workflow steps.

Windows is not currently supported.

## Security and integrity

- Supported releases are allowlisted.
- Downloads require HTTPS and are checked against committed SHA-256 digests.
- `expected-sha256` can add a caller-controlled digest assertion.
- Bundled cpm and the exact Carton bootstrap requirement are checked by
  `scripts/check-runtime`.
- Third-party Actions are pinned to full commit SHAs.

## Troubleshooting

### `minil new` reports missing Git identity

Configure `user.name` and `user.email` in the repository before running
commands that create Git commits:

```sh
git config user.name "Your Name"
git config user.email "you@example.com"
```

### The action uses dynamic resolution

No committed snapshot exactly matches the selected runner and Perl. The
installation remains usable, but persistent caching is disabled and transitive
dependencies are resolved from CPAN at runtime.

## Development

Run the local checks and lightweight tests:

```sh
make test
```

Run a real CPAN installation and Tool Cache reuse test:

```sh
make integration
```

Maintenance entry points:

- `scripts/update-runtime` refreshes bundled cpm and its manifest.
- `scripts/update-snapshots <version>` creates a snapshot for the current
  environment. It requires Carmel.
- `scripts/check-runtime` and `scripts/check-snapshots` detect committed
  artifact drift.

Snapshot installs bootstrap the exact Carton version declared in
`runtime/cpanfile` with cpm. Carton's transitive dependencies are dynamically
resolved because a Carton-format snapshot cannot bootstrap its own
`Carton::Snapshot` parser.

## License

This project is licensed under the MIT License. Bundled third-party components
retain their own licenses; see `THIRD_PARTY.md`.
