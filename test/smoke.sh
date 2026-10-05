#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

export RUNNER_TEMP="$temp_root/runner-temp"
export RUNNER_TOOL_CACHE="$temp_root/tool-cache"
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

if INPUT_VERSION=latest \
  GITHUB_OUTPUT="$temp_root/unsupported-output" \
  "$ROOT/scripts/setup-minil" 2>"$temp_root/unsupported-error"; then
  printf 'invalid version unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'version must use vX.Y.Z or X.Y.Z' "$temp_root/unsupported-error"

if [[ "${SETUP_MINIL_INTEGRATION:-false}" == "true" ]]; then
  test_version="${INPUT_VERSION:-v3.2.0}"
  test_version="v${test_version#v}"
  original_perl5lib="${PERL5LIB-}"
  export GITHUB_OUTPUT="${SETUP_MINIL_OUTPUT:-$temp_root/install-output}"
  export GITHUB_PATH="$temp_root/github-path"
  INPUT_VERSION="$test_version" "$ROOT/scripts/setup-minil"

  bin_path="$(cat "$GITHUB_PATH")"
  export PATH="$bin_path:$PATH"
  "$bin_path/minil" --version | grep -Fq "${test_version#v}"
  [[ "$bin_path" == "$RUNNER_TOOL_CACHE/minil/${test_version#v}/"*"/bin" ]]
  [[ -f "${bin_path%/bin}.complete" ]]
  grep -Fxq "version=$test_version" "$GITHUB_OUTPUT"
  grep -Eq '^resolution-mode=(snapshot|dynamic)$' "$GITHUB_OUTPUT"
  [[ "${PERL5LIB-}" == "$original_perl5lib" ]]

  GITHUB_PATH="$temp_root/reused-path" \
    INPUT_VERSION="$test_version" "$ROOT/scripts/setup-minil" >"$temp_root/reused-log"
  grep -q 'reusing Tool Cache installation' "$temp_root/reused-log"
  cmp "$temp_root/github-path" "$temp_root/reused-path"

  cp -R "$ROOT/test/fixtures/minimal-dist" "$temp_root/minimal-dist"
  (
    cd "$temp_root/minimal-dist"
    git init --quiet
    git config user.name "setup-minil test"
    git config user.email "setup-minil@example.invalid"
    git add .
    "$bin_path/minil" test 2>&1 | tee "$temp_root/minil-test.log"
    grep -q 'Result: PASS' "$temp_root/minil-test.log"
    "$bin_path/minil" dist 2>&1 | tee "$temp_root/minil-dist.log"
    grep -q 'Result: PASS' "$temp_root/minil-dist.log"
    test -s Example-Minilla-Dist-0.01.tar.gz
    tar -xOf Example-Minilla-Dist-0.01.tar.gz \
      Example-Minilla-Dist-0.01/LICENSE | grep -q 'MIT'
  )
fi
