use strict;
use warnings;
use Test::More;
use Getopt::Compact::WithCmd;

sub test_check_requires {
    my %specs = @_;
    my ($params, $expects, $desc) = @specs{qw/params expects desc/};

    subtest $desc => sub {
        my $go = bless {}, 'Getopt::Compact::WithCmd';
        $go->{opt}      = $params->{opt};
        $go->{requires} = $params->{requires};

        ok $expects ? $go->_check_requires : !$go->_check_requires, 'check_requires';
    };
}

test_check_requires(
    params => {
        opt      => {},
        requires => {},
    },
    expects => 1,
    desc => 'missing',
);

test_check_requires(
    params => {
        opt      => {
            foo => 1,
        },
        requires => {
            foo => 1,
        },
    },
    expects => 1,
    desc => 'ok',
);

test_check_requires(
    params => {
        opt      => {
            foo => undef,
        },
        requires => {
            foo => 1,
        },
    },
    expects => 0,
    desc => 'not ok',
);

done_testing;
