# setup-minil

`setup-minil` installs an allowlisted
[Minilla](https://metacpan.org/dist/Minilla) release with the Perl currently
selected on a GitHub Actions runner.

The installation is isolated under `RUNNER_TEMP`. The action adds only its
`bin` directory to `PATH` and does not modify the caller's `PERL5LIB`.

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

## Interface

| Input | Default | Description |
|---|---|---|
| `version` | `v3.2.0` | Exact allowlisted Minilla release |

| Output | Description |
|---|---|
| `version` | Installed Minilla version |

Only releases listed in `manifests/minilla.json` can be installed. The
downloaded release is always checked against its committed SHA-256 digest.

## Dependency resolution

The action uses an exact dependency snapshot when one matches the runner OS,
runner architecture, Perl version, and Perl `archname`. Otherwise it warns and
uses dynamic CPAN resolution.

Snapshot installs bootstrap the exact Carton version declared in
`runtime/cpanfile`. The action bundles only self-contained cpm; Carton and its
dependencies are not vendored.

See [`docs/specification.md`](docs/specification.md) for the complete current
behavior and maintenance model. A
[Japanese translation](docs/specification.ja.md) is also available.

## Development

```sh
make test
make integration
```

Snapshot maintenance runs on GitHub-hosted Ubuntu and macOS runners through
`.github/workflows/update-snapshots.yml`.

## License

This project is licensed under the MIT License. Bundled third-party components
retain their own licenses; see `THIRD_PARTY.md`.
