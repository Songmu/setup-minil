#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

action_root="$temp_root/action"
mkdir -p "$action_root/scripts" "$action_root/runtime" "$temp_root/runner-temp"
cp "$ROOT/scripts/setup-minil" "$action_root/scripts/setup-minil"
cp "$ROOT/runtime/cpanfile" "$ROOT/runtime/minilla.cpanfile" "$action_root/runtime/"

cat >"$action_root/runtime/cpm" <<'PERL'
use strict;
use warnings;
use File::Path qw(make_path);
open my $log, ">>", $ENV{CPM_LOG} or die $!;
print {$log} join(" ", @ARGV), "\n";
close $log or die $!;
die "missing recommends selection\n" unless grep $_ eq "--with-recommends", @ARGV;
die "missing runtime selection\n" unless grep $_ eq "--top-level-phase=runtime", @ARGV;
my ($cpanfile) = map { /^--cpanfile=(.*)$/ ? $1 : () } @ARGV;
die "missing cpanfile\n" unless defined $cpanfile;
open my $input, "<", $cpanfile or die $!;
my $content = do { local $/; <$input> };
my ($version) = $content =~ /requires 'Minilla', '== (v\d+\.\d+\.\d+)';/;
die "missing exact Minilla requirement\n" unless defined $version;
die "missing recommended dependency\n" unless $content =~ /recommends 'Software::License'/;
die "missing default build backend\n" unless $content =~ /requires 'Module::Build::Tiny'/;
my ($root) = map { /^--local-lib-contained=(.*)$/ ? $1 : () } @ARGV;
die "missing local-lib\n" unless defined $root;
make_path("$root/bin");
die "simulated installation failure\n" if $ENV{FAIL_INSTALL};
open my $fh, ">", "$root/bin/minil" or die $!;
print {$fh} "print qq(Minilla $version\\n);\n";
close $fh or die $!;
PERL

export RUNNER_TEMP="$temp_root/runner-temp"
export RUNNER_TOOL_CACHE="$temp_root/tool-cache"
export RUNNER_OS=Linux RUNNER_ARCH=X64
export CPM_LOG="$temp_root/cpm-log"
export GITHUB_PATH="$temp_root/github-path"
export GITHUB_OUTPUT="$temp_root/output"
cache_root="$RUNNER_TOOL_CACHE/minil/3.2.0/x64"

run_setup() {
  "$action_root/scripts/setup-minil" >"$temp_root/log" 2>"$temp_root/error"
}

assert_installs() {
  [[ "$(wc -l <"$CPM_LOG" | tr -d ' ')" == "$1" ]]
}

assert_clean_work() {
  [[ -z "$(find "$RUNNER_TEMP" -name 'setup-minil-work.*' -print)" ]]
  [[ -z "$(find "$RUNNER_TOOL_CACHE" -name '.x64.*' -print)" ]]
}

run_setup
[[ -f "$cache_root.complete" && -f "$cache_root/installation-id" ]]
[[ "$(cat "$GITHUB_PATH")" == "$cache_root/bin" ]]
assert_installs 1
assert_clean_work

run_setup
grep -q 'reusing Tool Cache installation' "$temp_root/log"
assert_installs 1
assert_clean_work

INPUT_VERSION=3.2.0 run_setup
grep -q 'reusing Tool Cache installation' "$temp_root/log"
assert_installs 1

rm "$cache_root.complete"
run_setup
assert_installs 2

printf 'wrong Perl environment\n' >"$cache_root/installation-id"
run_setup
assert_installs 3

rm "$cache_root/libexec/minil"
run_setup
assert_installs 4

printf '\n' >>"$action_root/runtime/cpanfile"
run_setup
assert_installs 5

printf '\n' >>"$action_root/runtime/minilla.cpanfile"
run_setup
assert_installs 6

RUNNER_OS=macOS run_setup
assert_installs 7

RUNNER_ARCH=ARM64 run_setup
[[ -f "$RUNNER_TOOL_CACHE/minil/3.2.0/arm64.complete" ]]
assert_installs 8

INPUT_VERSION=v3.1.0 run_setup
[[ -f "$RUNNER_TOOL_CACHE/minil/3.1.0/x64.complete" ]]
assert_installs 9

rm "$cache_root.complete"
if FAIL_INSTALL=true run_setup; then
  printf 'simulated installation failure unexpectedly succeeded\n' >&2
  exit 1
fi
grep -q 'simulated installation failure' "$temp_root/error"
[[ ! -e "$cache_root.complete" && ! -e "$cache_root" ]]
assert_clean_work

env -u RUNNER_TOOL_CACHE "$action_root/scripts/setup-minil" >"$temp_root/log" 2>"$temp_root/error"
[[ -f "$RUNNER_TEMP/setup-minil-tool-cache/minil/3.2.0/x64.complete" ]]
assert_clean_work
