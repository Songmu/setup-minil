# Changelog

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
