# setup-minil

`setup-minil` installs a specified
[Minilla](https://metacpan.org/dist/Minilla) release with the Perl currently
selected on a GitHub Actions runner.

The installation is isolated in the Runner Tool Cache. The action adds only
its `bin` directory to `PATH` and does not modify the caller's `PERL5LIB`.

Matching completed installations are reused. The action does not use
`actions/cache` or expose cache controls.

## Usage

Select Perl before running this action:

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: shogo82148/actions-setup-perl@8b574cdc2dffdae49f803204a4f2b716a2fa1db7 # v1.44.2
    with:
      perl-version: "5.40"

  - uses: Songmu/setup-minil@<full-commit-sha>

  - run: minil --version
```

Pinning this action to a full commit SHA is recommended.

## Interface

| Input | Default | Description |
|---|---|---|
| `version` | `v3.2.0` | Exact Minilla release, in `vX.Y.Z` or `X.Y.Z` form |

| Output | Description |
|---|---|
| `version` | Installed Minilla version |

Minilla is installed from CPAN by cpm with an exact version requirement.
There is no release allowlist or Action-managed tarball digest verification.

## Dependency resolution

The action uses an exact dependency snapshot when one matches the runner OS,
runner architecture, Perl version, and Perl `archname`. Otherwise it warns and
uses dynamic CPAN resolution.

Snapshot installs bootstrap the exact Carton version declared in
`runtime/cpanfile`. The action bundles only self-contained cpm; Carton and its
dependencies are not vendored.

The recommended modules listed in `runtime/minilla.cpanfile` are declared as
direct requirements, including the modules used for non-Perl licenses, release
testing, and CPAN uploads.

See [`docs/specification.md`](docs/specification.md) for the complete current
behavior and maintenance model. A
[Japanese translation](docs/specification.ja.md) is also available.

## Development

```sh
make test
make integration
```

`make test` runs the offline regression suite with `prove -v t`; you can also run
`prove -v t` directly.

Installer and maintenance scripts use the selected Perl's core modules. The
offline regression suite in `t/` shares a cpm fixture; integration checks exercise
the same Minilla distribution fixture locally and in CI.

Snapshot maintenance runs on GitHub-hosted Ubuntu and macOS runners through
`.github/workflows/update-snapshots.yml`.

Releases are prepared by tagpr. Merging its release pull request creates a
SemVer tag and GitHub Release, then the tagpr workflow moves the `v0` tag to
the new release for major-version Action references.

## License

This project is licensed under the MIT License. Bundled third-party components
retain their own licenses; see `THIRD_PARTY.md`.
