#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../scripts";
use SetupMinil qw(write_file read_file environment snapshot_path);
use Cwd           qw(abs_path);
use File::Copy     qw(cp);
use File::Basename qw(basename);
use File::Glob     qw(bsd_glob);
use File::Path     qw(make_path);
use File::Temp     qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;
use JSON::PP qw(decode_json);

my $root = tempdir( 'setup minil.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
make_path( "$root/scripts", "$root/runtime", "$root/snapshots", "$root/temp" );
for my $script ( bsd_glob("$SetupMinil::ROOT/scripts/*") ) {
    cp( $script, "$root/scripts/" . basename($script) ) or die $!;
}
for my $file (qw(cpanfile minilla.cpanfile)) {
    cp( "$SetupMinil::ROOT/runtime/$file", "$root/runtime/$file" ) or die $!;
}
cp( "$SetupMinil::ROOT/t/cpm-fixture", "$root/runtime/cpm" ) or die $!;
my $manifest_path = "$root/runtime/manifest.json";
# Fixture versions do not track Renovate-managed runtime releases.
write_file( $manifest_path, '{"minilla":{"version":"v3.2.0"}}' );

my %fixture_environment = (
    RUNNER_OS         => 'Linux',
    RUNNER_ARCH       => 'X64',
    RUNNER_TEMP       => "$root/temp",
    RUNNER_TOOL_CACHE => "$root/cache",
    CPM_LOG           => "$root/cpm-log",
    FIXTURE_PERL      => $SetupMinil::PERL,
    GITHUB_PATH       => "$root/path",
    GITHUB_OUTPUT     => "$root/output",
);
@ENV{ keys %fixture_environment } = values %fixture_environment;
delete $ENV{INPUT_VERSION};

sub invoke {
    my $error  = gensym;
    my $pid    = open3( undef, my $out, $error, $SetupMinil::PERL, @_ );
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$error> };
    waitpid( $pid, 0 );
    return ( $?, $stdout . $stderr );
}

sub succeeds {
    my ( $status, $text ) = invoke(@_);
    is( $status, 0, "@_" ) or diag $text;
}

sub rejects {
    my ( $pattern, @command ) = @_;
    my ( $status,  $text )    = invoke(@command);
    ok( $status && $text =~ $pattern, "rejects $pattern" ) or diag $text;
}

subtest 'shared module helpers' => sub {
    succeeds(
        '-I', "$root/scripts", '-MSetupMinil', '-e',
        'die "read_file exported by default\n" if defined &main::read_file'
    );

    for my $content ( '', "first line\nsecond line\n" ) {
        my $path = "$root/read-file";
        write_file( $path, $content );
        is( read_file($path), $content, 'read_file returns the entire file, including empty files' );
    }

    my @cases = (
        [
            'run', 'run($^X, "-e", q{print join "|", @ARGV}, "arg one", "arg two")',
            'arg one|arg two', 'run preserves command arguments',
        ],
        [
            'run_in',
            'my $before = Cwd::getcwd(); '
              . 'run_in($ARGV[0], $^X, "-MCwd", "-e", q{print Cwd::getcwd()}); '
              . 'die "working directory changed\n" unless Cwd::getcwd() eq $before',
            abs_path("$root/temp"), 'run_in changes and restores the working directory',
        ],
        [
            'run_in',
            'my $before = Cwd::getcwd(); '
              . 'eval { run_in($ARGV[0], $^X, "-e", "exit 7") }; '
              . 'die "missing command failure\n" unless $@ =~ /command failed/; '
              . 'die "working directory changed\n" unless Cwd::getcwd() eq $before; '
              . 'print "restored\n"',
            "restored\n", 'run_in restores the working directory after command failure',
        ],
        [
            'run_quiet',
            'run_quiet($^X, "-e", q{print "hidden\n"}); print "restored\n"',
            "restored\n", 'run_quiet suppresses command output and restores stdout',
        ],
        [
            'run_quiet',
            'eval { run_quiet($^X, "-e", "exit 7") }; '
              . 'die "missing command failure\n" unless $@ =~ /command failed/; '
              . 'print "restored\n"',
            "restored\n", 'run_quiet restores stdout after command failure',
        ],
    );
    for my $case (@cases) {
        my ( $helper, $code, $expected, $description ) = @$case;
        my ( $status, $text ) =
          invoke( '-I', "$root/scripts", "-MSetupMinil=$helper", '-e', $code, "$root/temp" );
        is( $status, 0, "$description: exit status" ) or diag $text;
        is( $text, $expected, $description );
    }
};

my $setup    = "$root/scripts/setup-minil";
my $checker  = "$root/scripts/check-snapshots";
my $cache    = "$root/cache/minil/3.2.0/x64";
my $installs = 0;

sub setup {
    my ($expected) = @_;
    succeeds($setup);
    my @invocations = split /\n/, read_file("$root/cpm-log");
    is( scalar @invocations, $expected, 'cpm invocation count' );

    my @temporary_directories = (
        bsd_glob("$root/temp/setup-minil-work.*"),
        bsd_glob("$root/cache/minil/*/.*??????"),
    );
    is_deeply( \@temporary_directories, [], 'temporary directories cleaned' );
}

setup( ++$installs );
ok( -f "$cache.complete" && -f "$cache/libexec/minil", 'completed Tool Cache entry' );
like(
    read_file("$root/cpm-log"),
    qr/--local-lib-contained=\Q$cache\E --home=/,
    'installed directly into final Tool Cache directory'
);
ok( -f "$cache/lib/perl5/InstalledPath.pm", 'installed dependency retained' );
is( read_file("$root/path"), "$cache/bin\n", 'only isolated bin exported' );
like(
    read_file("$root/output"),
    qr/version=v3.2.0\nresolution-mode=dynamic\n/,
    'normalized outputs'
);
setup($installs);

{
    local $ENV{INPUT_VERSION} = '3.2.0';
    setup($installs);
}

for my $file ( "$cache.complete", "$cache/installation-id", "$cache/libexec/minil" ) {
    unlink $file or die $!;
    setup( ++$installs );
}

for my $file (qw(cpanfile minilla.cpanfile)) {
    write_file( "$root/runtime/$file", read_file("$root/runtime/$file") . "\n" );
    setup( ++$installs );
}

{
    local $ENV{RUNNER_OS} = 'macOS';
    setup( ++$installs );
}

{
    local $ENV{RUNNER_ARCH} = 'ARM64';
    setup( ++$installs );
    ok( -f "$root/cache/minil/3.2.0/arm64.complete", 'architecture slot' );
}

{
    local $ENV{INPUT_VERSION} = 'v3.1.0';
    setup( ++$installs );
    ok( -f "$root/cache/minil/3.1.0/x64.complete", 'version slot' );
}

unlink "$cache.complete" or die $!;
{
    local $ENV{FAIL_INSTALL} = 1;
    rejects( qr/simulated installation failure/, $setup );
    ++$installs;
}
ok( !-e $cache && !-e "$cache.complete", 'failed installation cleaned without completion marker' );
is_deeply( [ bsd_glob("$root/temp/*"), bsd_glob("$root/cache/minil/3.2.0/.*??????") ],
    [], 'failure cleanup' );
write_file( "$cache/partial-installation", 'incomplete' );
setup( ++$installs );
ok( !-e "$cache/partial-installation", 'partial installation removed before retry' );

unlink "$cache.complete" or die $!;
{
    local $ENV{FAIL_WRAPPER} = 1;
    rejects( qr/simulated wrapper failure/, $setup );
    ++$installs;
}
ok( !-e $cache && !-e "$cache.complete", 'wrapper failure cleans incomplete installation' );
is_deeply( [ bsd_glob("$root/temp/*") ], [], 'wrapper failure cleans working files' );
setup( ++$installs );

{
    local $ENV{FAIL_WRAPPER} = 1;
    rejects( qr/simulated wrapper failure/, $setup );
}
ok( -f "$cache.complete" && -f "$cache/libexec/minil", 'reused installation is not removed on failure' );
setup($installs);

{
    local $ENV{RUNNER_TOOL_CACHE};
    delete $ENV{RUNNER_TOOL_CACHE};
    succeeds($setup);
    ++$installs;

    ok( -f "$root/temp/setup-minil-tool-cache/minil/3.2.0/x64.complete", 'fallback cache' );
}

my @rejected_inputs = (
    [ INPUT_VERSION => 'latest',  qr/version must use/ ],
    [ RUNNER_OS     => 'Windows', qr/unsupported operating system/ ],
    [ RUNNER_ARCH   => 'other',   qr/unsupported architecture/ ],
);
for my $case (@rejected_inputs) {
    my ( $name, $value, $message ) = @$case;
    local $ENV{$name} = $value;
    rejects( $message, $setup );
}

succeeds($checker);
succeeds( "$root/scripts/update-snapshots", '3.2.0' );
++$installs;
my $env       = environment('v3.2.0');
my $directory = "$root/snapshots/" . snapshot_path($env);
my $metadata  = decode_json( read_file("$directory/environment.json") );
is_deeply( { map { $_ => $metadata->{$_} } keys %$env }, $env, 'exact generator environment' );
is( $metadata->{generator}{carmel_version}, 'v0.1.56', 'generator provenance' );

for my $file (qw(cpanfile cpanfile.snapshot environment.json)) {
    my $content = read_file("$directory/$file");
    unlink "$directory/$file" or die $!;
    rejects( qr/missing snapshot file/, $checker );
    write_file( "$directory/$file", $content );
}

rename $directory, "$directory-wrong" or die $!;
rejects( qr/snapshot path does not match/, $checker );
rename "$directory-wrong", $directory or die $!;

make_path("$root/snapshots/v3.2.0/empty");
rejects( qr/missing snapshot file/, $checker );
rmdir "$root/snapshots/v3.2.0/empty" or die $!;

setup( $installs + 2 );    # Snapshot installation invokes cpm for both Carton and Minilla.
like(
    read_file("$root/cpm-log"),
    qr/--resolver=snapshot --no-default-resolvers/,
    'snapshot-only resolution'
);
like( read_file("$root/output"), qr/resolution-mode=snapshot/, 'snapshot output' );

subtest 'manifest version selection' => sub {
    local $ENV{RUNNER_TOOL_CACHE} = "$root/version-cache";
    local $ENV{CPM_LOG}           = "$root/version-cpm-log";
    local $ENV{GITHUB_PATH}       = "$root/version-path";
    local $ENV{GITHUB_OUTPUT}     = "$root/version-output";
    my $original = read_file($manifest_path);
    write_file( $manifest_path, '{"minilla":{"version":"v9.8.7"}}' );

    my ( $status, $version ) =
      invoke( '-I', "$root/scripts", '-MSetupMinil=default_version', '-e', 'print default_version()' );
    is( $status, 0, 'read default from a Perl one-liner' );
    is( $version, 'v9.8.7', 'read the fixture manifest rather than the repository default' );

    for my $case (
        [ undef,   'v9.8.7', 'omitted input uses manifest default' ],
        [ '',      'v9.8.7', 'empty input uses manifest default' ],
        [ '1.2.3', 'v1.2.3', 'explicit input overrides manifest default' ],
      )
    {
        my ( $input, $expected, $description ) = @$case;
        local $ENV{INPUT_VERSION} = $input;
        write_file( $ENV{GITHUB_OUTPUT}, '' );
        succeeds($setup);
        like( read_file($ENV{GITHUB_OUTPUT}), qr/^version=\Q$expected\E$/m, $description );
    }

    for my $invalid ( {}, { minilla => { version => 'latest' } } ) {
        write_file( $manifest_path, JSON::PP->new->encode($invalid) );
        rejects( qr/invalid default Minilla version/, $setup );
    }
    write_file( $manifest_path, $original );
};

done_testing;
