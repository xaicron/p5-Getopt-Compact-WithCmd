use inc::Module::Install;
name 'Getopt-Compact-WithCmd';
all_from 'lib/Getopt/Compact/WithCmd.pm';

requires 'Text::Table';

build_requires 'Test::More', 0.88;
test_requires 'Test::Output';

tests_recursive 't';
author_tests 'xt';

auto_include();
auto_set_repository();

WriteAll;
