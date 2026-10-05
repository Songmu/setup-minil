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

run_prepare() {
  local output="$1"
  export GITHUB_OUTPUT="$output"
  INPUT_VERSION=v3.2.0 INPUT_CACHE=false "$ROOT/scripts/setup-minil" prepare
}

prepare_output="$temp_root/prepare-output"
run_prepare "$prepare_output"
grep -q '^resolution-mode=' "$prepare_output"
grep -q '^cache-enabled=false$' "$prepare_output"
resolution_mode="$(awk -F= '$1 == "resolution-mode" { print $2 }' "$prepare_output")"
state_path="$(awk -F= '$1 == "state-path" { print substr($0, index($0, "=") + 1) }' "$prepare_output")"
[[ -f "$state_path" ]]

if PREPARED_STATE="$state_path" \
  INPUT_VERSION=v3.2.0 \
  INPUT_CACHE=false \
  INPUT_EXPECTED_SHA256=invalid \
  RESTORE_CACHE_HIT=false \
  GITHUB_OUTPUT="$temp_root/rejected-output" \
  "$ROOT/scripts/setup-minil" install 2>"$temp_root/rejected-error"; then
  printf 'invalid expected-sha256 unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'does not match the allowlisted digest' "$temp_root/rejected-error"

if INPUT_VERSION=v0.0.0 \
  INPUT_CACHE=false \
  GITHUB_OUTPUT="$temp_root/unsupported-output" \
  "$ROOT/scripts/setup-minil" prepare 2>"$temp_root/unsupported-error"; then
  printf 'unsupported version unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'unsupported Minilla version' "$temp_root/unsupported-error"

if [[ "${SETUP_MINIL_INTEGRATION:-false}" == "true" ]]; then
  export GITHUB_OUTPUT="$temp_root/install-output"
  export GITHUB_PATH="$temp_root/github-path"
  PREPARED_STATE="$state_path" \
    INPUT_VERSION=v3.2.0 \
    INPUT_CACHE=false \
    RESTORE_CACHE_HIT=false \
    "$ROOT/scripts/setup-minil" install

  bin_path="$(cat "$GITHUB_PATH")"
  "$bin_path/minil" --version | grep -q 'v3.2.0'
  grep -q '^tool-cache-hit=false$' "$GITHUB_OUTPUT"

  cp -R "$ROOT/test/fixtures/minimal-dist" "$temp_root/minimal-dist"
  (
    cd "$temp_root/minimal-dist"
    git init --quiet
    git config user.name "setup-minil test"
    git config user.email "setup-minil@example.invalid"
    git add .
    "$bin_path/minil" test
  )

  : >"$temp_root/reuse-output"
  GITHUB_OUTPUT="$temp_root/reuse-output" \
    PREPARED_STATE="$state_path" \
    INPUT_VERSION=v3.2.0 \
    INPUT_CACHE=false \
    RESTORE_CACHE_HIT=false \
    "$ROOT/scripts/setup-minil" install
  grep -q '^tool-cache-hit=true$' "$temp_root/reuse-output"

  if [[ "$resolution_mode" == "snapshot" ]]; then
    cache_prepare_output="$temp_root/cache-prepare-output"
    GITHUB_OUTPUT="$cache_prepare_output" \
      INPUT_VERSION=v3.2.0 \
      INPUT_CACHE=true \
      "$ROOT/scripts/setup-minil" prepare
    grep -q '^cache-enabled=true$' "$cache_prepare_output"
    cache_state_path="$(awk -F= '$1 == "state-path" { print substr($0, index($0, "=") + 1) }' "$cache_prepare_output")"

    GITHUB_OUTPUT="$temp_root/cache-save-output" \
      PREPARED_STATE="$cache_state_path" \
      INPUT_VERSION=v3.2.0 \
      INPUT_CACHE=true \
      RESTORE_CACHE_HIT=false \
      "$ROOT/scripts/setup-minil" install
    grep -q '^cache-save=true$' "$temp_root/cache-save-output"

    GITHUB_OUTPUT="$temp_root/cache-restore-output" \
      PREPARED_STATE="$cache_state_path" \
      INPUT_VERSION=v3.2.0 \
      INPUT_CACHE=true \
      RESTORE_CACHE_HIT=true \
      "$ROOT/scripts/setup-minil" install
    grep -q '^persistent-cache-hit=true$' "$temp_root/cache-restore-output"
    grep -q '^cache-save=false$' "$temp_root/cache-restore-output"
  fi
fi
