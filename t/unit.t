#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../scripts";
use SetupMinil;
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
ok( -f "$cache.complete" && -f "$cache/libexec/minil", 'published Tool Cache entry' );
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
ok( !-e $cache && !-e "$cache.complete", 'failed installation not published' );
is_deeply( [ bsd_glob("$root/temp/*"), bsd_glob("$root/cache/minil/3.2.0/.*??????") ],
    [], 'failure cleanup' );

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

done_testing;
