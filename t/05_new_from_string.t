use strict;
use warnings;
use Test::More;
use Test::Requires 'Text::ParseWords';

use File::Basename qw/basename/;
use Getopt::Compact::WithCmd;

subtest 'ok' => sub {
    my $opts = Getopt::Compact::WithCmd->new_from_string('--foo',
        global_struct => {
            foo => { type => '!' },
        },
    )->opts;
    is $opts->{foo}, 1;
};

subtest 'fail' => sub {
    eval { Getopt::Compact::WithCmd->new_from_string() };
    like $@, qr/Usage: Getopt::Compact::WithCmd->new_from_string\(\$str, %options\)/;
};

done_testing;
