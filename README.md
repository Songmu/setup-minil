# setup-minil

Install an exact [Minilla](https://metacpan.org/dist/Minilla) release with the
Perl selected on a Linux or macOS GitHub Actions runner (Perl 5.24+, X64/ARM64).
Completed, compatible installations are reused in the Runner Tool Cache.
Only the isolated `bin` is added to `PATH`; the caller's `PERL5LIB` is unchanged.
The action does not use `actions/cache` or expose cache controls.

## Usage

Select Perl first and pin actions to full commit SHAs:

```yaml
steps:
  - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262
  - uses: shogo82148/actions-setup-perl@8b574cdc2dffdae49f803204a4f2b716a2fa1db7
    with:
      perl-version: "5.40"
  - uses: Songmu/setup-minil@<full-commit-sha>
  - run: minil --version
```

## Interface

| Input | Default | Description |
|---|---|---|
| `version` | `v3.2.0` | Exact Minilla release, `vX.Y.Z` or `X.Y.Z` |

The `version` output is the installed version normalized to `vX.Y.Z`.

## Dependency resolution

Bundled cpm installs Minilla from CPAN with an exact requirement. An exact
OS/architecture/Perl-version/archname snapshot is used when available; otherwise
the action warns and resolves dynamically. Snapshot installs bootstrap pinned
Carton from `runtime/cpanfile`; Carton and its dependencies are not vendored.
`runtime/minilla.cpanfile` includes the default build backend and recommended
modules for licenses, release testing, and CPAN uploads, installed with
`--with-recommends`. There is no release allowlist or action-managed release
digest verification. See [the specification](docs/specification.md) for details.

## Development

```sh
make test         # offline regression tests and runtime checks
make integration  # real CPAN installation and minil test/dist
```

`scripts/update-snapshots <version>` generates a snapshot for the current
environment. `.github/workflows/update-snapshots.yml` generates Ubuntu/macOS
snapshots, verifies installations, and opens a Draft PR.

## License

MIT. Bundled components retain their own licenses; see `THIRD_PARTY.md`.
