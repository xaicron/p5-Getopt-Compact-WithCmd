use strict;
use warnings;
use Test::More;
use Getopt::Compact::WithCmd;

sub test_parse_struct {
    my %specs = @_;

    my ($struct, $expects, $opts, $desc) = @specs{qw/struct expects opts desc/};

    subtest $desc => sub {
        my $go = bless $opts ? $opts : {}, 'Getopt::Compact::WithCmd';
        $go->{struct}   = $struct;
        $go->{opt}      = {};
        $go->{requires} = {};

        my $got = $go->_parse_struct();
        my $opt_map = { map { $_ => 1 } keys %$got };

        is_deeply $opt_map, $expects->{opt_map}, 'opt map';
        is_deeply $go->{opt}, $expects->{opt}, 'opt';
        is_deeply $go->{requires}, $expects->{requires}, 'requires';

        done_testing;
    };
}

test_parse_struct(
    struct  => [],
    expects => {
        opt_map  => {},
        opt      => {},
        requires => {},
    },
    desc => 'missing',
);

test_parse_struct(
    struct  => [
        [ [qw/f foo/], 'foo' ],
    ],
    expects => {
        opt_map => {
            'f|foo' => 1,
        },
        opt => {
            foo => undef,
        },
        requires => {},
    },
    desc => 'minimal',
);

test_parse_struct(
    struct  => [
        [ [qw/f foo/], 'foo', '=s' ],
        [ [qw/b bar/], 'bar', '!' ],
        [ [qw/baz/], 'baz', ':i' ],
    ],
    expects => {
        opt_map => {
            'f|foo=s' => 1,
            'b|bar!'  => 1,
            'baz:i'   => 1,
        },
        opt => {
            foo => undef,
            bar => undef,
            baz => undef,
        },
        requires => {},
    },
    desc => 'with type',
);

test_parse_struct(
    struct  => [
        [ [qw/f foo/], 'foo', '=s', \my $foo ],
    ],
    expects => {
        opt_map => {
            'f|foo=s' => 1,
        },
        opt => {},
        requires => {},
    },
    desc => 'with bind',
);

test_parse_struct(
    struct  => [
        [ [qw/f foo/], 'foo', '=s', \my $foo2, { default => 'hoge' } ],
        [ [qw/b bar/], 'bar', '!', undef, { default => 1 } ],
    ],
    expects => {
        opt_map => {
            'f|foo=s' => 1,
            'b|bar!'  => 1,
        },
        opt => {
            bar => 1,
        },
        requires => {},
    },
    desc => 'with default',
);

test_parse_struct(
    struct  => [
        [ [qw/f foo/], 'foo', '=s', undef, { default => 'hoge', required => 1 } ],
        [ [qw/b bar/], 'bar', '!', undef, { default => 1, required => 0 } ],
    ],
    expects => {
        opt_map => {
            'f|foo=s' => 1,
            'b|bar!'  => 1,
        },
        opt => {
            foo => 'hoge',
            bar => 1,
        },
        requires => {
            foo => 1,
        },
    },
    desc => 'with required',
);

done_testing;
