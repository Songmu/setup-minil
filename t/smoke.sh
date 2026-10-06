#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT
test_version="${INPUT_VERSION:-$(perl -I "$ROOT/scripts" -MSetupMinil=default_version -e 'print default_version()')}"
test_version="v${test_version#v}"

if [[ -z "${SETUP_MINIL_BIN:-}" ]]; then
  export RUNNER_TEMP="$temp_root/runner-temp" RUNNER_TOOL_CACHE="$temp_root/tool-cache"
  original_perl5lib="${PERL5LIB-}"
  export GITHUB_OUTPUT="${SETUP_MINIL_OUTPUT:-$temp_root/install-output}"
  export GITHUB_PATH="$temp_root/github-path"
  INPUT_VERSION="$test_version" "$ROOT/scripts/setup-minil"

  bin_path="$(cat "$GITHUB_PATH")"
  [[ "$bin_path" == "$RUNNER_TOOL_CACHE/minil/${test_version#v}/"*"/bin" ]]
  [[ -f "${bin_path%/bin}.complete" ]]
  grep -Fxq "version=$test_version" "$GITHUB_OUTPUT"
  grep -Eq '^resolution-mode=(snapshot|dynamic)$' "$GITHUB_OUTPUT"
  [[ "${PERL5LIB-}" == "$original_perl5lib" ]]

  GITHUB_PATH="$temp_root/reused-path" \
    INPUT_VERSION="$test_version" "$ROOT/scripts/setup-minil" >"$temp_root/reused-log"
  grep -q 'reusing Tool Cache installation' "$temp_root/reused-log"
  cmp "$temp_root/github-path" "$temp_root/reused-path"
else
  bin_path="$SETUP_MINIL_BIN"
fi
export PATH="$bin_path:$PATH"
"$bin_path/minil" --version >/dev/null 2>&1
cp -R "$ROOT/t/fixtures/minimal-dist" "$temp_root/minimal-dist"
cd "$temp_root/minimal-dist"
git init --quiet
git config user.name "setup-minil test"
git config user.email "setup-minil@example.invalid"
git add .
for command in test dist; do
  "$bin_path/minil" --no-auto-install "$command"
done
test -s Example-Minilla-Dist-0.01.tar.gz
tar -xOf Example-Minilla-Dist-0.01.tar.gz Example-Minilla-Dist-0.01/LICENSE | grep -q 'MIT'
