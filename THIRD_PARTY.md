# Third-party components

This repository vendors the following runtime components:

| Component | Version | Source | License |
|---|---|---|---|
| App::cpm | v1.1.5 | `skaji/cpm` | Artistic License 2.0 |

Carton v1.0.35 is installed dynamically into an isolated temporary local-lib
only when snapshot resolution is used. It is not vendored in this repository
and does not modify the runner's global Perl installation.
