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

mkdir -p "$temp_root/runtime" "$temp_root/bin"
cp "$ROOT/scripts/update-snapshots" "$temp_root/scripts/update-snapshots"
cp "$ROOT/runtime/minilla.cpanfile" "$temp_root/runtime/"
cat >"$temp_root/bin/carmel" <<'SH'
#!/usr/bin/env bash
printf 'existing Carmel must not be reused\n' >&2
exit 1
SH
chmod +x "$temp_root/bin/carmel"

cat >"$temp_root/runtime/cpm" <<'PERL'
use strict;
use warnings;
use File::Path qw(make_path);
die "bootstrap used the wrong Perl\n" unless $^X eq $ENV{SNAPSHOT_PERL};
my ($root) = map { /^--local-lib-contained=(.*)$/ ? $1 : () } @ARGV;
die "missing local-lib\n" unless defined $root;
make_path("$root/bin", "$root/lib/perl5");
open my $module, ">", "$root/lib/perl5/CarmelFixture.pm" or die $!;
print {$module} "package CarmelFixture; 1;\n";
close $module or die $!;
open my $script, ">", "$root/bin/carmel" or die $!;
print {$script} <<'CARMEL';
#!/nonexistent/perl
use strict;
use warnings;
use CarmelFixture;
die "Carmel used the wrong Perl\n" unless $^X eq $ENV{SNAPSHOT_PERL};
if ($ARGV[0] eq 'version') {
    print "v0.1.56\n";
} elsif ($ARGV[0] eq 'install') {
    open my $snapshot, ">", "cpanfile.snapshot" or die $!;
    print {$snapshot} "# fixture snapshot\n";
    close $snapshot or die $!;
} else {
    die "unexpected Carmel command\n";
}
CARMEL
close $script or die $!;
chmod 0755, "$root/bin/carmel" or die $!;
PERL

PATH="$temp_root/bin:$PATH" SNAPSHOT_PERL="$(perl -e 'print $^X')" \
  RUNNER_OS=Linux RUNNER_ARCH=X64 GITHUB_OUTPUT="$temp_root/generator-output" \
  "$temp_root/scripts/update-snapshots" v3.2.0 >"$temp_root/generator-log"
generated_path="$(sed -n 's/^snapshot-path=//p' "$temp_root/generator-output")"
[[ -f "$temp_root/snapshots/$generated_path/cpanfile.snapshot" ]]
perl -MConfig -MJSON::PP -0777 -e '
    my $metadata = decode_json(<>);
    die "wrong Perl version\n" unless $metadata->{perl_version} eq $Config{version};
    die "wrong Perl archname\n" unless $metadata->{perl_archname} eq $Config{archname};
    die "missing generator version\n" unless $metadata->{generator}{carmel_version} eq "v0.1.56";
' "$temp_root/snapshots/$generated_path/environment.json"

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
