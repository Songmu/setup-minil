# Changelog

## [v0.0.1](https://github.com/Songmu/setup-minil/commits/v0.0.1) - 2026-10-05

- Implement setup-minil action by @Songmu in https://github.com/Songmu/setup-minil/pull/1
- Consolidate installer logic and regression tests by @Songmu in https://github.com/Songmu/setup-minil/pull/2
- Update GitHub Actions and fix ghalint policies by @Songmu in https://github.com/Songmu/setup-minil/pull/6
- Add tagpr release automation by @Songmu in https://github.com/Songmu/setup-minil/pull/7
- Add Minilla v3.2.0 snapshots from successful workflow run by @Songmu in https://github.com/Songmu/setup-minil/pull/9
- Fix snapshot workflow input and use Perl test directory by @Songmu in https://github.com/Songmu/setup-minil/pull/10
- Test committed snapshots without regeneration by @Songmu in https://github.com/Songmu/setup-minil/pull/11
- Add Renovate tracking for Minilla and cpm by @Songmu in https://github.com/Songmu/setup-minil/pull/12
- Require Minilla recommendations directly by @Songmu in https://github.com/Songmu/setup-minil/pull/13

## Unreleased

- Add the initial `setup-minil` composite Action.
- Install specified Minilla releases from CPAN into an isolated Runner Tool Cache
  directory and reuse matching completed installations.
- Add dynamic dependency resolution and exact-environment snapshot support.
- Include Minilla's runtime recommended dependencies by default in both
  dynamic installations and generated snapshots.
- Bundle a verified self-contained cpm and bootstrap an exact Carton version
  only when snapshot resolution needs it.
- Generate supported snapshots on GitHub-hosted runners using their system
  Perl installations.
