#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT
temp_root="$(CDPATH= cd -- "$temp_root" && pwd -P)"

mkdir -p "$temp_root/scripts" "$temp_root/snapshots"
cp "$ROOT/scripts/check-snapshots" "$temp_root/scripts/check-snapshots"
checker="$temp_root/scripts/check-snapshots"
directory="$temp_root/snapshots/v3.2.0/linux-x64-perl-5.40.0-x86_64-linux"

write_snapshot() {
  mkdir -p "$directory"
  printf "requires 'Minilla', '== v3.2.0';\n" >"$directory/cpanfile"
  printf '# fixture snapshot\n' >"$directory/cpanfile.snapshot"
  cat >"$directory/environment.json" <<'JSON'
{
  "runner_os": "Linux",
  "runner_arch": "X64",
  "perl_version": "5.40.0",
  "perl_archname": "x86_64-linux",
  "minilla_version": "v3.2.0"
}
JSON
}

assert_rejected() {
  local expected="$1"
  if "$checker" >"$temp_root/output" 2>"$temp_root/error"; then
    printf 'invalid snapshot unexpectedly succeeded: %s\n' "$expected" >&2
    exit 1
  fi
  grep -Fq "$expected" "$temp_root/error"
}

"$checker"
mkdir -p "$temp_root/snapshots/v3.2.0"
"$checker"

write_snapshot
"$checker"

for file in cpanfile cpanfile.snapshot environment.json; do
  rm "$directory/$file"
  assert_rejected "missing snapshot file: $directory/$file"
  write_snapshot
done

empty_directory="$temp_root/snapshots/v3.2.0/linux-arm64-perl-5.40.0-aarch64-linux"
mkdir -p "$empty_directory"
assert_rejected "missing snapshot file: $empty_directory/cpanfile"
rmdir "$empty_directory"

mv "$directory" "$directory-wrong"
assert_rejected 'snapshot path does not match its environment'
mv "$directory-wrong" "$directory"
"$checker"
