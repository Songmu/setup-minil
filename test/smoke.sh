#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

export RUNNER_TEMP="$temp_root/runner-temp"
mkdir -p "$RUNNER_TEMP"

case "$(uname -s)" in
  Darwin) export RUNNER_OS=macOS ;;
  Linux) export RUNNER_OS=Linux ;;
  *) printf 'unsupported test operating system\n' >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) export RUNNER_ARCH=X64 ;;
  arm64|aarch64) export RUNNER_ARCH=ARM64 ;;
  *) printf 'unsupported test architecture\n' >&2; exit 1 ;;
esac

if INPUT_VERSION=v0.0.0 \
  GITHUB_OUTPUT="$temp_root/unsupported-output" \
  "$ROOT/scripts/setup-minil" 2>"$temp_root/unsupported-error"; then
  printf 'unsupported version unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'unsupported Minilla version' "$temp_root/unsupported-error"

if [[ "${SETUP_MINIL_INTEGRATION:-false}" == "true" ]]; then
  original_perl5lib="${PERL5LIB-}"
  export GITHUB_OUTPUT="${SETUP_MINIL_OUTPUT:-$temp_root/install-output}"
  export GITHUB_PATH="$temp_root/github-path"
  INPUT_VERSION=v3.2.0 "$ROOT/scripts/setup-minil"

  bin_path="$(cat "$GITHUB_PATH")"
  "$bin_path/minil" --version | grep -q 'v3.2.0'
  grep -q '^version=v3.2.0$' "$GITHUB_OUTPUT"
  grep -Eq '^resolution-mode=(snapshot|dynamic)$' "$GITHUB_OUTPUT"
  [[ "${PERL5LIB-}" == "$original_perl5lib" ]]

  cp -R "$ROOT/test/fixtures/minimal-dist" "$temp_root/minimal-dist"
  (
    cd "$temp_root/minimal-dist"
    git init --quiet
    git config user.name "setup-minil test"
    git config user.email "setup-minil@example.invalid"
    git add .
    "$bin_path/minil" test
  )
fi
