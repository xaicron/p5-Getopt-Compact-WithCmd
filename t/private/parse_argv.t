use strict;
use warnings;
use Test::More;
use Getopt::Compact::WithCmd;

sub test_parse_argv {
    my %specs = @_;

    my ($input, $expects, $desc) = @specs{qw/input expects desc/};

    subtest $desc => sub {
        local @ARGV = @$input;
        my @opts = Getopt::Compact::WithCmd->_parse_argv;

        is_deeply \@opts, $expects, 'parse argv';

        done_testing;
    };
};

test_parse_argv(
    input   => [],
    expects => [],
    desc    => 'empty',
);

test_parse_argv(
    input   => [qw/--foo/],
    expects => [qw/--foo/],
    desc    => 'simple',
);

test_parse_argv(
    input   => [qw/--foo bar/],
    expects => [qw/--foo/],
    desc    => 'with cmd',
);

test_parse_argv(
    input   => [qw/--foo=bar/],
    expects => [qw/--foo=bar/],
    desc    => 'string argv',
);

test_parse_argv(
    input   => [qw/--foo=bar baz/],
    expects => [qw/--foo=bar/],
    desc    => 'string argv with cmd',
);

done_testing;
