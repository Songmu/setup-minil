# Third-party components

## Bundled cpm

This repository vendors the self-contained cpm executable, including its
embedded dependencies:

| Component | Version | Source | License |
|---|---|---|---|
| App::cpm | v1.1.5 | `skaji/cpm` | Artistic License 2.0 |

The bundled executable is pinned to upstream commit
`1e93312a5e801b1f3a27182309a8e62c16e9d7c5`. Its provenance and SHA-256 digest
are recorded in [`runtime/manifest.json`](runtime/manifest.json).

## Embedded distributions and notices

The header of [`runtime/cpm`](runtime/cpm) retains upstream's original notices
for the following 25 embedded distributions. Copyright holders and license
declarations below are transcribed from that header; distribution source URLs
are also retained there. Individual embedded distribution versions are not
listed in the header and are not asserted separately here.

| Distribution | Copyright notice | Declared license |
|---|---|---|
| CPAN-02Packages-Search | Shoichi Kaji | the same as Perl 5 |
| CPAN-DistnameInfo | Graham Barr | the same as Perl 5 |
| Capture-Tiny | David Golden | Apache 2.0 |
| Command-Runner | Shoichi Kaji | the same as Perl 5 |
| Darwin-InitObjC | Shoichi Kaji | the same as Perl 5 |
| ExtUtils-Config | Ken Williams, Leon Timmermans | the same as Perl 5 |
| ExtUtils-Helpers | Ken Williams, Leon Timmermans | the same as Perl 5 |
| ExtUtils-Install | Yves Orton, Michael Schwern, Alan Burlison, Randy W. Sims and others | the same as Perl 5 |
| ExtUtils-InstallPaths | Ken Williams, Leon Timmermans. | the same as Perl 5 |
| ExtUtils-PL2Bat | Leon Timmermans. | the same as Perl 5 |
| File-Copy-Recursive | Daniel Muey | the same as Perl 5 |
| File-Which | Per Einar Ellefsen | the same as Perl 5 |
| File-pushd | David A Golden | the same as Perl 5 |
| HTTP-Tinyish | Tatsuhiko Miyagawa | the same as Perl 5 |
| IPC-Run3 | R. Barrie Slaymaker, Jr. | the BSD, Artistic, or GPL licenses, any version |
| Module-CPANfile | Tatsuhiko Miyagawa | the same as Perl 5 |
| Module-cpmfile | Shoichi Kaji | the same as Perl 5 |
| Parallel-Pipes | Shoichi Kaji | the same as Perl 5 |
| Parse-LocalDistribution | Andreas Koenig, Kenichi Ishigaki | the same as Perl 5 |
| Parse-PMFile | Andreas Koenig, Kenichi Ishigaki | the same as Perl 5 |
| Proc-ForkSafe | Shoichi Kaji | the same as Perl 5 |
| String-ShellQuote | Roderick Schertler | the same as Perl 5 |
| Tie-Handle-Offset | David Golden | Apache 2.0 |
| Win32-ShellQuote | Graham Knop, CONTRIBUTORS | the same as Perl 5 |
| YAML-PP | Tina M&uuml;ller | the same as Perl 5 |

These declarations are distinct from App::cpm's Artistic License 2.0.
The project's MIT license does not replace the bundled components' licenses.

## Dependencies installed at runtime

Carton v1.0.35 is installed dynamically into an isolated temporary local-lib
only when snapshot resolution is used. It is not vendored in this repository
and does not modify the runner's global Perl installation.

Minilla, its recommended modules, and Carmel (used to generate snapshots) are
also installed from CPAN rather than vendored.
