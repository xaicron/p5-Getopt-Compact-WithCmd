use inc::Module::Install;
name 'Getopt-Compact-WithCmd';
all_from 'lib/Getopt/Compact/WithCmd.pm';

#requires '';

build_requires 'Test::More', 0.88;
#test_requires 'Test::Requires';

tests_recursive 't';
author_tests 'xt';

auto_include();
auto_set_repository();

WriteAll;
