#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../scripts";
use SetupMinil qw(read_file write_file);
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;
use JSON::PP ();

my $workflow = read_file("$FindBin::Bin/../.github/workflows/update-snapshots.yml");

sub step_script {
    my ($name) = @_;
    $workflow =~ /      - name: \Q$name\E\n.*?        run: \|\n((?:          [^\n]*\n|\n)+)/s
      or die "missing workflow step: $name\n";
    my $script = $1;
    $script =~ s/^          //mg;
    return $script;
}

sub execute {
    my ( $directory, @command ) = @_;
    my $error = gensym;
    my $pid = open3( undef, my $out, $error, 'bash', '-euo', 'pipefail', '-c',
        'cd -- "$1"; shift; exec "$@"', 'workflow-test', $directory, @command );
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$error> };
    waitpid( $pid, 0 );
    return ( $?, $stdout . $stderr );
}

sub git {
    my ( $directory, @arguments ) = @_;
    my ( $status, $text ) = execute( $directory, 'git', @arguments );
    die $text if $status;
    return $text;
}

my $guard = step_script('Verify the pull request only changes Minilla snapshot files');
my $publish = step_script('Commit generated snapshots');
my $json = JSON::PP->new->canonical;

for my $case (
    [ 'default version update', 'v3.2.1', undef, undef, 0, 'true' ],
    [ 'unchanged default version', 'v3.2.0', undef, undef, 0, 'false' ],
    [ 'cpm-only update', 'v3.2.0', 'new', undef, 0, 'false' ],
    [ 'generated snapshots', 'v3.2.1', undef, 'snapshots/v3.2.1/Linux/X64/test', 0, 'true' ],
    [ 'unrelated file', 'v3.2.1', undef, 'scripts/unrelated', 1, undef ],
    [ 'older release snapshot', 'v3.2.1', undef, 'snapshots/v3.2.0/test', 1, undef ],
    [ 'other runtime change', 'v3.2.1', 'new', undef, 1, undef ],
    [ 'invalid version', 'latest', undef, undef, 1, undef ],
) {
    my ( $name, $version, $cpm, $extra, $failure, $changed ) = @$case;
    subtest $name => sub {
        my $root = tempdir( CLEANUP => 1 );
        my $remote = "$root/remote";
        my $repo = "$root/repo";
        mkdir $remote or die $!;
        mkdir $repo or die $!;
        git( $remote, 'init', '--bare', '--quiet' );
        git( $repo, 'init', '--quiet', '-b', 'main' );
        git( $repo, 'config', 'user.name', 'Workflow test' );
        git( $repo, 'config', 'user.email', 'workflow@example.invalid' );
        git( $repo, 'remote', 'add', 'origin', $remote );
        my $manifest = { minilla => { version => 'v3.2.0' }, cpm => { version => 'old' } };
        write_file( "$repo/runtime/manifest.json", $json->encode($manifest) );
        write_file( "$repo/scripts/check-snapshots", "#!/bin/sh\nexit 0\n" );
        chmod 0755, "$repo/scripts/check-snapshots" or die $!;
        git( $repo, 'add', '.' );
        git( $repo, 'commit', '--quiet', '-m', 'Base runtime' );
        git( $repo, 'push', '--quiet', 'origin', 'main' );
        git( $repo, 'switch', '--quiet', '-c', 'renovate/minilla' );
        $manifest->{minilla}{version} = $version;
        $manifest->{cpm}{version} = $cpm if defined $cpm;
        write_file( "$repo/runtime/manifest.json", $json->encode($manifest) );
        write_file( "$repo/$extra", 'fixture' ) if defined $extra;
        git( $repo, 'add', '.' );
        git( $repo, 'commit', '--quiet', '--allow-empty', '-m', 'Dependency update' );
        git( $repo, 'push', '--quiet', 'origin', 'HEAD' );
        git( $repo, 'checkout', '--quiet', '--detach' );

        local $ENV{BASE_REF} = 'main';
        local $ENV{GITHUB_OUTPUT} = "$root/output";
        my ( $status, $text ) = execute( $repo, 'bash', '-euo', 'pipefail', '-c', $guard );
        is( !!$status, !!$failure, 'guard exit status' ) or diag $text;
        if ( defined $changed ) {
            is( read_file("$root/output"), "minilla-changed=$changed\n", 'generation decision' );
        }
        return if $failure || $changed ne 'true';

        write_file( "$root/bin/gh", "#!/bin/sh\nprintf '%s\\n' \"\$*\" >>\"\$GH_LOG\"\n" );
        chmod 0755, "$root/bin/gh" or die $!;
        local $ENV{PATH} = "$root/bin:$ENV{PATH}";
        local $ENV{GH_LOG} = "$root/gh-log";
        local $ENV{GH_TOKEN} = 'fixture';
        local $ENV{VERSION} = $version;
        local $ENV{HEAD_REF} = 'renovate/minilla';
        local $ENV{DEFAULT_BRANCH} = 'main';
        local $ENV{GITHUB_RUN_ID} = '123';
        local $ENV{GITHUB_EVENT_NAME} = 'pull_request';
        write_file( "$repo/snapshots/$version/Linux/X64/test", 'generated' );
        my $old_head = git( $repo, 'rev-parse', 'HEAD' );
        ( $status, $text ) = execute( $repo, 'bash', '-euo', 'pipefail', '-c', $publish );
        is( $status, 0, 'publish from detached PR head' ) or diag $text;
        my $head = git( $repo, 'rev-parse', 'HEAD' );
        isnt( $head, $old_head, 'snapshot commit created' );
        is( git( $repo, 'rev-parse', 'origin/renovate/minilla' ), $head, 'same PR branch updated' );
        is( read_file("$root/gh-log"), "workflow run ci.yml --ref renovate/minilla\n", 'CI dispatched without a new PR' );

        ( $status, $text ) = execute( $repo, 'bash', '-euo', 'pipefail', '-c', $publish );
        is( $status, 0, 'already-current snapshots succeed' ) or diag $text;
        is( git( $repo, 'rev-parse', 'HEAD' ), $head, 'no redundant commit' );
        is( read_file("$root/gh-log"), "workflow run ci.yml --ref renovate/minilla\n", 'no redundant CI dispatch' );

        git( $repo, 'commit', '--quiet', '--allow-empty', '-m', 'Concurrent PR update' );
        git( $repo, 'push', '--quiet', 'origin', 'HEAD:renovate/minilla' );
        my $new_head = git( $repo, 'rev-parse', 'HEAD' );
        chomp $head;
        git( $repo, 'checkout', '--quiet', '--detach', $head );
        write_file( "$repo/snapshots/$version/Linux/X64/test", 'stale refresh' );
        ( $status, $text ) = execute( $repo, 'bash', '-euo', 'pipefail', '-c', $publish );
        ok( $status, 'concurrent PR update rejects stale snapshot push' );
        is( git( $repo, 'rev-parse', 'origin/renovate/minilla' ), $new_head, 'newer PR commit preserved' );
        is( read_file("$root/gh-log"), "workflow run ci.yml --ref renovate/minilla\n", 'failed push does not dispatch CI' );

        local $ENV{GITHUB_EVENT_NAME} = 'workflow_dispatch';
        write_file( "$repo/snapshots/$version/Linux/X64/test", 'manual refresh' );
        ( $status, $text ) = execute( $repo, 'bash', '-euo', 'pipefail', '-c', $publish );
        is( $status, 0, 'manual dispatch publishes snapshots' ) or diag $text;
        like( read_file("$root/gh-log"), qr/pr create --draft .*--base main --head automation\/update-snapshots-3\.2\.1-123\n$/, 'manual dispatch still creates a Draft PR' );
    };
}

done_testing;
