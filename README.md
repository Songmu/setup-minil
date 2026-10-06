# setup-minil

`setup-minil` installs [Minilla](https://metacpan.org/dist/Minilla) on a
GitHub Actions runner and makes `minil` available on `PATH`.

## Usage

Use the action on a Linux or macOS runner:

```yaml
steps:
  - uses: Songmu/setup-minil@v0
  - run: minil --version
```

`@v0` follows releases in the `v0` series. You can also use an exact release tag
or pin the action to a full commit SHA (recommended for reproducible workflows).

## Inputs and outputs

| Input | Default | Description |
|---|---|---|
| `version` | `minilla.version` in [`runtime/manifest.json`](runtime/manifest.json) | Exact Minilla release, in `vX.Y.Z` or `X.Y.Z` form |

| Output | Description |
|---|---|
| `version` | Installed Minilla version |

To select a Minilla release, set `version`:

```yaml
- uses: Songmu/setup-minil@v0
  with:
    version: "v3.2.0"
```

## Documentation

See the [specification](docs/specification.md) for installation behavior,
dependency resolution, caching, development, and maintenance details. A
[Japanese translation](docs/specification.ja.md) is also available.

## License

This project is licensed under the MIT License. Bundled third-party components
retain their own licenses; see `THIRD_PARTY.md`.
