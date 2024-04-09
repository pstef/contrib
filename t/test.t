# -*- perl -*-

use strict;
use warnings;

use Test::More;
use File::Find ();
use Capture::Tiny ':all';

use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;
my $num_plugins = 0;

sub wanted {
    my ( $dev, $ino, $mode, $nlink, $uid, $gid, $interpreter, $arguments );

    ( ( $dev, $ino, $mode, $nlink, $uid, $gid ) = lstat($_) )
        && -f _
        && -s _
        && ( ( $interpreter, $arguments ) = hashbang("$_") )
        && ($interpreter)
        && ++$num_plugins
        && process_file( $_, $name, $interpreter, $arguments );
}

File::Find::find( { wanted => \&wanted, no_chdir => 1 }, 'plugins' );

sub hashbang {
    my ($filename) = @_;
    open my $file, '<', $filename;
    my $firstline = <$file>;
    close $file;

    $firstline =~ m{ ^\#!                    # hashbang
                     \s*                     # optional space
                     (?:/usr/bin/env\s+)?    # optional /usr/bin/env
                     (?<interpreter>\S+)     # interpreter
                     (?:\s+
                         (?<arguments>[^\n]*)   # optional interpreter arguments
                     )?
               }xms;

    return ( $+{interpreter}, $+{arguments} );
}

sub process_file {
    my ( $file, $filename, $interpreter, $arguments ) = @_;
    use v5.10.1;

    if ( -r "$file.nocheck") {
    SKIP: {
            skip( sprintf("\nFile '%s' has a .nocheck flag. Ignoring\n", $file), 1);
            pass("Not pretending everything is ok");
        }
    }
    elsif ( ! -x $file ) {
        # missing executable flag
        diag(
            sprintf("\nFile '%s' lacks executable permission bits. Maybe try 'chmod +x $file'?\n",
                    $file)
        );
    }
    elsif ( $interpreter =~ m{/bin/sh} ) {
        subtest $filename => sub {
            plan tests => 3;
            run_check(
                {   command     => [ 'sh', '-n', $file ],
                    description => 'sh syntax check'
                }
            );
            my $checkbashisms_location = `command -v checkbashisms 2>/dev/null`;
            chomp($checkbashisms_location);
            my $command;
            if ($checkbashisms_location ne "") {
                # monkey-patch "checkbashisms" in order to allow "command -v"
                # see https://unix.stackexchange.com/a/85250: "command -v" vs. which/hash/...
                # see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=733511
                my $run_modified_checkbashisms = q/sed 's#command\\\s+-\[\^p\]#command\s+-[^pvV]#'/
                    . " '$checkbashisms_location' | perl - '$file'";
                $command = [ 'sh', '-c', $run_modified_checkbashisms ];
            } else {
                # make sure that the non-confusing "checkbashisms not found" message is displayed
                $command = [ 'checkbashisms', $file ];
            }
            run_check(
                {   command     => $command,
                    description => 'checkbashisms'
                }
            );
            run_check(
                {   command     => [ 't/test-exception-wrapper', $file, 'shellcheck', '--exclude=SC1090,SC2009,SC2126,SC2230', '--shell=dash' ],
                    description => 'shellcheck'
                }
            );
        };
    }
    elsif ( $interpreter =~ m{/bin/ksh} ) {
        subtest $filename => sub {
            plan tests => 2;
            run_check(
                {   command     => [ 'ksh', '-n', $file ],
                    description => 'ksh syntax check',
                    filename    => $filename
                }
            );
            run_check(
                {   command     => [ 't/test-exception-wrapper', $file, 'shellcheck', '--shell=ksh' ],
                    description => 'shellcheck'
                }
            );
        }
    }
    elsif ( $interpreter =~ m{bash} ) {
        subtest $filename => sub {
            plan tests => 2;
            run_check(
                {   command     => [ 'bash', '-n', $file ],
                    description => 'bash syntax check',
                    filename    => $filename
                }
            );
            run_check(
                {   command     => [ 't/test-exception-wrapper', $file, 'shellcheck', '--exclude=SC1090,SC2009,SC2126,SC2230', '--shell=bash' ],
                    description => 'shellcheck'
                }
            );
        }
    }
    elsif ( $interpreter =~ m{/bin/zsh} ) {
        run_check(
            {   command     => [ 'zsh', '-n', $file ],
                description => 'zsh syntax check',
                filename    => $filename
            }
        );
    }
    elsif ( $interpreter =~ m{perl} ) {
        my $command;
        if ( $arguments =~ m{-.*T}mx ) {
            $command = [ 'perl', '-cwT', $file ];
        }
        else {
            $command = [ 'perl', '-cw', $file ];
        }
        run_check(
            {   command     => $command,
                description => 'perl syntax check',
                filename    => $filename
            }
        );
    }
    elsif ( $interpreter =~ m{python3} ) {
        subtest $filename => sub {
            plan tests => 2;
            run_check(
                {   command     => [ 'python3', '-m', 'py_compile', $file ],
                    description => 'python3 compile',
                    filename    => $filename
                }
            );
            run_check(
                {   command     => [ 't/test-exception-wrapper', $file, 'python3', '-m', 'flake8' ],
                    description => 'python3-flake8'
                }
            );
        }
    }
    elsif ( $interpreter =~ m{python} ) {
        subtest $filename => sub {
            plan tests => 2;
            run_check(
                {   command     => [ 'python', '-m', 'py_compile', $file ],
                    description => 'python compile',
                    filename    => $filename
                }
            );
            run_check(
                {   command     => [ 't/test-exception-wrapper', $file, 'python', '-m', 'flake8' ],
                    description => 'python-flake8'
                }
            );
        }
    }
    elsif ( $interpreter =~ m{php} ) {
        run_check(
            {   command     => [ 'php', '-l', $file ],
                description => 'php syntax check',
                filename    => $filename
            }
        );
    }
    elsif ( $interpreter =~ m{j?ruby} ) {
        subtest $filename => sub {
            plan tests => 2;
            run_check(
                {   command     => [ 'ruby', '-cw', $file ],
                    description => 'ruby syntax check',
                    filename    => $filename
                }
            );
            run_check(
                {   command     => [ 't/test-exception-wrapper', $file, 'rubocop' ],
                    description => 'ruby style and syntax check',
                    filename    => $filename
                }
            );
        }
    }
    elsif ( $interpreter =~ m{gawk} ) {
        run_check(
            {   command => [
                    'gawk', '--source', 'BEGIN { exit(0) } END { exit(0) }',
                    '--file', $file
                ],
                description => 'gawk syntax check',
                filename    => $filename
            }
        );
    }
    elsif ( $interpreter =~ m{expect} ) {
    SKIP: {
            skip 'no idea how to check expect scripts', 1;
            pass("No pretending everything is ok");
        }
    }
    else {
        fail( $filename . " unknown interpreter " . $interpreter );
    }
}

sub run_check {
    my ($args)        = @_;
    my $check_command = $args->{command};
    my $description   = $args->{description};
    my $filename      = $args->{filename};

    my $message;

    if ($filename) {
        $message = sprintf( '%s: %s', $filename, $description );
    }
    else {
        $message = $description;
    }

    my ( $stdout, $stderr, $exit ) = capture {
        system( @{$check_command} );
    };

    ok( ( $exit == 0 ), $message );

    if ($exit) {
        diag(
            sprintf(
                "\nCommand: %s\n\nSTDOUT:\n\n%s\n\nSTDERR:\n\n%s\n\n",
                join( " ", @{$check_command} ),
                $stdout, $stderr
            )
        );
    }
}

done_testing($num_plugins);
