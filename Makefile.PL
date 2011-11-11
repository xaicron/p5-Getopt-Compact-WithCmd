use inc::Module::Install;
name 'Getopt-Compact-WithCmd';
all_from 'lib/Getopt/Compact/WithCmd.pm';

requires 'Text::Table';
requires 'Getopt::Long', '2.38';
recommends 'Text::ParseWords';

test_requires 'Test::More', 0.96;
test_requires 'Test::Output';
test_requires 'Test::Requires';

tests_recursive 't';
author_tests 'xt';

auto_set_repository();

WriteAll;
