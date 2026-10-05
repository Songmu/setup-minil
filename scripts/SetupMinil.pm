package SetupMinil;
use strict;
use warnings;
use Config;
use Cwd qw(abs_path getcwd);
use Digest::SHA qw(sha256_hex);
use Exporter 'import';
use File::Basename qw(dirname);
use File::Glob qw(bsd_glob);
use File::Path qw(make_path);
use FindBin;
use JSON::PP qw(decode_json);

our @EXPORT = qw(read_file write_file digest run run_in run_quiet cpm environment snapshot_path check_snapshot output decode_json bsd_glob);
our $ROOT = abs_path("$FindBin::Bin/..");
our $PERL = abs_path($^X =~ m{/} ? $^X : $Config{perlpath}) or die "cannot locate selected Perl\n";

sub read_file {
    open my $fh, '<', $_[0] or die "$_[0]: $!\n";
    local $/;
    return <$fh>;
}
sub write_file {
    my ($path, $content, $mode) = @_;
    make_path(dirname($path)) unless $mode && $mode eq '>>';
    open my $fh, $mode || '>', $path or die "$path: $!\n";
    print {$fh} $content or die "$path: $!\n";
    close $fh or die "$path: $!\n";
}
sub digest { sha256_hex(read_file($_[0])) }
sub run {
    (system { $_[0] } @_) == 0 or die "setup-minil: command failed (@_): $?\n";
}
sub run_in {
    my $directory = shift;
    my $previous = getcwd();
    chdir $directory or die "$directory: $!\n";
    my $status = system { $_[0] } @_;
    chdir $previous or die "$previous: $!\n";
    $status == 0 or die "setup-minil: command failed (@_): $status\n";
}
sub run_quiet {
    open my $saved, '>&', \*STDOUT or die "saving stdout: $!\n";
    open STDOUT, '>', '/dev/null' or die "/dev/null: $!\n";
    my $status = system { $_[0] } @_;
    open STDOUT, '>&', $saved or die "restoring stdout: $!\n";
    $status == 0 or die "setup-minil: command failed (@_): $status\n";
}
sub cpm {
    my ($destination, $home, $perl_args, @args) = @_;
    run_in(dirname($home), $PERL, @$perl_args, "$ROOT/runtime/cpm", 'install', @args,
        '--mirror=https://cpan.metacpan.org/', "--local-lib-contained=$destination",
        "--home=$home", '--exclude-vendor', '--no-prebuilt', '--no-test');
}
sub environment {
    my $version = shift;
    $version =~ s/^v//;
    $version =~ /^\d+\.\d+\.\d+$/ or die "version must use vX.Y.Z or X.Y.Z\n";
    $] >= 5.024 or die "cpm v1 requires Perl 5.24 or later; selected Perl is $Config{version}\n";
    my $os = $ENV{RUNNER_OS} || `uname -s`;
    my $arch = $ENV{RUNNER_ARCH} || `uname -m`;
    chomp($os, $arch);
    $os = 'macOS' if $os eq 'Darwin';
    $arch = 'X64' if $arch =~ /^(?:x86_64|amd64)$/;
    $arch = 'ARM64' if $arch =~ /^(?:aarch64|arm64)$/;
    $os =~ /^(?:Linux|macOS)$/ or die "unsupported operating system: $os\n";
    $arch =~ /^(?:X64|ARM64)$/ or die "unsupported architecture: $arch\n";
    return { minilla_version => "v$version", runner_os => $os, runner_arch => $arch,
        perl_version => $Config{version}, perl_archname => $Config{archname} };
}
sub snapshot_path {
    my ($env) = @_;
    my $name = lc join '-', @{$env}{qw(runner_os runner_arch)}, 'perl',
        @{$env}{qw(perl_version perl_archname)};
    $name =~ s/[^a-z0-9_.-]/_/g;
    return "$env->{minilla_version}/$name";
}
sub check_snapshot {
    my ($directory, $expected) = @_;
    -f "$directory/$_" or die "missing snapshot file: $directory/$_\n"
        for qw(cpanfile cpanfile.snapshot environment.json);
    my $env = decode_json(read_file("$directory/environment.json"));
    for my $field (qw(minilla_version runner_os runner_arch perl_version perl_archname)) {
        defined $env->{$field} && length $env->{$field} or die "missing $field in $directory/environment.json\n";
        !$expected || $env->{$field} eq $expected->{$field}
            or die "$directory/environment.json: expected $field=$expected->{$field}\n";
    }
    $env->{minilla_version} =~ /^v\d+\.\d+\.\d+$/ or die "invalid Minilla version in $directory/environment.json\n";
    my $relative = snapshot_path($env);
    $directory =~ m{/\Q$relative\E$}
        or die "snapshot path does not match its environment: $directory\n";
}
sub output {
    my ($name, $value) = @_;
    write_file($ENV{GITHUB_OUTPUT} || '/dev/stdout', "$name=$value\n", '>>');
}
1;
