package Getopt::Compact::WithCmd;

use strict;
use warnings;
use 5.008_001;
use Data::Dumper ();
use List::Util qw(max);
use Getopt::Long qw/GetOptionsFromArray/;
use constant DEFAULT_CONFIG => (no_auto_abbrev => 1, bundling => 1);

our $VERSION = '0.14';

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        cmd         => $args{cmd} || do { require File::Basename; File::Basename::basename($0) },
        name        => $args{name},
        version     => $args{version} || $::VERSION,
        modes       => $args{modes},
        opt         => {},
        usage       => exists $args{usage} && !$args{usage} ? 0 : 1,
        args        => $args{args} || '',
        _argv       => \@ARGV,
        struct      => [],
        summary     => {},
        requires    => {},
        ret         => 0,
        error       => undef,
        other_usage => undef,
        commands    => [],
        _struct     => $args{command_struct} || {},
    }, $class;

    my %config = (DEFAULT_CONFIG, %{$args{configure} || {}});
    my @gconf = grep $config{$_}, keys %config;
    Getopt::Long::Configure(@gconf) if @gconf;

    $self->_init_summary($args{command_struct});

    if (my $global_struct = $args{global_struct}) {
        $self->_init_struct($global_struct);
        my $opthash = $self->_parse_struct || return $self;

        if ($args{command_struct}) {
            if (my @gopts = $self->_parse_argv) {
                $self->{ret} = $self->_parse_option(\@gopts, $opthash);
                return $self unless $self->{ret};
                return $self if $self->_want_help;
            }
            $self->_check_requires;
        }
        else {
            $self->{ret} = $self->_parse_option(\@ARGV, $opthash);
            return $self unless $self->{ret};
            return $self if $self->_want_help;
            $self->_check_requires;
            return $self;
        }
    }

    $self->_parse_command_struct($args{command_struct});

    return $self;
}

sub new_from_array {
    my ($class, $args, %options) = @_;
    unless (ref $args eq 'ARRAY') {
        require Carp;
        Carp::croak("Usage: $class->new_from_array(\\\@args, %options)");
    }
    local @ARGV = @$args;
    return $class->new(%options);
}

sub command    { $_[0]->{command}  }
sub commands   { $_[0]->{commands} }
sub status     { $_[0]->{ret}      }
sub is_success { $_[0]->{ret}      }
sub pod2usage  { require Carp; Carp::carp('Not implemented') }

sub opts {
    my($self) = @_;
    my $opt = $self->{opt};
    if ($self->{usage} && ($opt->{help} || $self->status == 0)) {
        # display usage message & exit
        print $self->usage;
        exit !$self->status;
    }
    return $opt;
}

sub usage {
    my($self, @targets) = @_;
    my $usage = '';
    my(@help, @commands);

    if ((defined $self->command && $self->command eq 'help') || @targets) {
        delete $self->{command};
        @targets = @{$self->{_argv}} unless @targets;
        for (my $i = 0; $i < @targets; $i++) {
            my $target = $targets[$i];
            last unless defined $target;
            unless (ref $self->{_struct}{$target} eq 'HASH') {
                $self->{error} = "Unknown command: $target";
                last;
            }
            else {
                $self->{command} = $target;
                push @{$self->{commands}}, $target;
                $self->_init_struct($self->{_struct}{$target}{options});
                $self->_extends_usage($self->{_struct}{$target});

                if (ref $self->{_struct}{$target}{command_struct} eq 'HASH') {
                    $self->{_struct} = $self->{_struct}{$target}{command_struct};
                }
                else {
                    $self->{summary} = {};
                }
            }
        }
    }

    my($name, $version, $cmd, $struct, $args, $summary, $error, $other_usage) = map
        $self->{$_} || '', qw/name version cmd struct args summary error other_usage/;

    $usage .= "$error\n" if $error;

    if ($name) {
        $usage .= $name;
        $usage .= " v$version" if $version;
        $usage .= "\n";
    }

    if ($self->command && $self->command ne 'help') {
        my $sub_command = join q{ }, @{$self->commands} ? @{$self->commands} : $self->command;
        $usage .= "usage: $cmd $sub_command [options]";
    }
    else {
        $usage .= "usage: $cmd [options]";
        $usage .= ' COMMAND' if keys %$summary;
    }
    $usage .= ($args ? " $args" : '') . "\n\n";

    for my $o (@$struct) {
        my ($name_spec, $desc, $arg_spec, $dist, $opts) = @$o;
        $desc = '' unless defined $desc;
        my @onames = $self->_option_names($name_spec);
        my $optname = join
            (', ', map { (length($_) > 1 ? '--' : '-').$_ } @onames);
        $optname = '    '.$optname unless length($onames[0]) == 1;
        my $info = do {
            local $Data::Dumper::Indent = 0;
            local $Data::Dumper::Terse  = 1;
            my $info = [];
            push @$info, $arg_spec                ? $self->_opt_spec2name($arg_spec): '';
            push @$info, $opts->{required}        ? "(required)" : '';
            push @$info, defined $opts->{default} ? "(default: ".Data::Dumper::Dumper($opts->{default}).")" : '';
            $info;
        };
        push @help, [ $optname, $info, ucfirst($desc) ];
    }

    if (@help) {
        require Text::Table;
        my $sep = \'   ';
        $usage .= "options:\n";
        $usage .= Text::Table->new($sep, '', $sep, '', $sep, '')->load($self->_format_info(@help))->stringify."\n";
    }

    if (defined $other_usage && length $other_usage > 0) {
        $other_usage =~ s/\n$//ms;
        $usage .= "$other_usage\n\n";
    }

    if (!$self->command || $self->{has_sub_command}) {
        for my $command (sort keys %$summary) {
            push @commands, [ $command, ucfirst $summary->{$command} ];
        }

        if (@commands) {
            require Text::Table;
            my $sep = \'   ';
            $usage .= "Implemented commands are:\n";
            $usage .= Text::Table->new($sep, '', $sep, '')->load(@commands)->stringify."\n";
            my $help_command = "$cmd help COMMAND";
            if (@{$self->commands}) {
                my $sub_commands = join q{ }, @{$self->commands};
                $help_command = "$cmd $sub_commands COMMAND --help";
            }
            $usage .= "See '$help_command' for more information on a specific command.\n\n";
        }
    }

    return $usage;
}

sub show_usage {
    my $self = shift;
    print $self->usage(@_);
    exit !$self->status;
}

sub _opt_spec2name {
    my ($self, $spec) = @_;
    my $name = '';
    my ($type, $dest) = $spec =~ /^[=:]?([!+isof])([@%])?/;
    if ($type) {
        $name =
            $type eq '!' ? 'Bool'   :
            $type eq '+' ? 'Incr'   :
            $type eq 's' ? 'Str'    :
            $type eq 'i' ? 'Int'    :
            $type eq 'o' ? 'ExtInt' :
            $type eq 'f' ? 'Number' : '';
    }
    if ($dest) {
        $name .= $dest eq '@' ? ':Array' : $dest eq '%' ? ':Hash' : '';
    }
    return $name;
}

sub _format_info {
    my ($self, @help) = @_;

    my $type_max     = 0;
    my $required_max = 0;
    my $default_max  = 0;
    for my $row (@help) {
        my ($type, $required, $default) = @{$row->[1]};
        $type_max     = max $type_max, length($type);
        $required_max = max $required_max, length($required);
        $default_max  = max $default_max, length($default);
    }

    for my $row (@help) {
        my ($type, $required, $default) = @{$row->[1]};
        my $parts = [];
        for my $stuff ([$type_max, $type], [$required_max, $required], [$default_max, $default]) {
            push @$parts, sprintf '%-*s', @$stuff if $stuff->[0] > 0;
        }
        $row->[1] = join ' ', @$parts;
    }

    return @help;
}

sub _parse_command_struct {
    my ($self, $command_struct) = @_;
    $command_struct ||= {};

    my $command_map = { map { $_ => 1 } keys %$command_struct };
    my $command = shift @ARGV;
    unless ($command) {
        $self->{ret} = $self->_check_requires;
        return $self;
    }

    unless ($command_map->{help}) {
        $command_map->{help} = 1;
        $command_struct->{help} = {
            args => '[COMMAND]',
            desc => 'show help message',
        };
    }

    unless (exists $command_map->{$command}) {
        $self->{error} = "Unknown command: $command";
        $self->{ret} = 0;
        return $self;
    }

    $self->{command} ||= $command;

    if ($command eq 'help') {
        $self->{ret} = 0;
        delete $self->{error};
        if (defined $ARGV[0] && exists $command_struct->{$ARGV[0]}) {
            my $nested_struct = $command_struct->{$ARGV[0]}{command_struct};
            $self->_init_nested_struct($nested_struct) if $nested_struct;
        }
        return $self;
    }

    push @{$self->{commands} ||= []}, $command;
    $self->_init_struct($command_struct->{$command}{options});
    $self->_extends_usage($command_struct->{$command});
    my $opthash = $self->_parse_struct || return $self;

    if (my $nested_struct = $command_struct->{$command}{command_struct}) {
        $self->_init_nested_struct($nested_struct);

        my @opts = $self->_parse_argv;
        $self->{ret} = $self->_parse_option(\@opts, $opthash);
        $self->_check_requires;
        if ($self->_want_help) {
            delete $self->{error};
            $self->{ret} = 0;
        }
        return $self unless $self->{ret};
        $self->_parse_command_struct($nested_struct);
    }
    else {
        $self->{ret} = $self->_parse_option(\@ARGV, $opthash);
        $self->_check_requires;
        $self->{has_sub_command} = 0;
        if ($self->_want_help) {
            delete $self->{error};
            $self->{ret} = 0;
        }
    }

    return $self;
}

sub _want_help {
    exists $_[0]->{opt}{help} && $_[0]->{opt}{help} ? 1 : 0;
}

sub _init_nested_struct {
    my ($self, $nested_struct) = @_;
    $self->{summary} = {}; # reset
    $self->_init_summary($nested_struct);
    $self->{has_sub_command} = 1;
}

sub _parse_option {
    my ($self, $argv, $opthash) = @_;
    local $SIG{__WARN__} = sub {
        $self->{error} = join '', @_;
        chomp $self->{error};
    };
    my $ret = GetOptionsFromArray($argv, %$opthash) ? 1 : 0;
    return $ret;
}

sub _parse_argv {
    my @opts;
    while (@ARGV) {
        last unless $ARGV[0] =~ /^-/;
        push @opts, shift @ARGV;
    }
    return @opts;
}

sub _parse_struct {
    my ($self) = @_;
    my $struct = $self->{struct};

    my $opthash = {};
    my $default_opthash = {};
    my $default_args = [];
    for my $s (@$struct) {
        my($m, $descr, $spec, $ref, $opts) = @$s;
        my @onames = $self->_option_names($m);
        my($longname) = grep length($_) > 1, @onames;
        my $o = join('|', @onames).($spec || '');
        my $dest = $longname ? $longname : $onames[0];
        $opts ||= {};
        if (exists $opts->{default}) {
            my $value = $opts->{default};
            if (ref $value eq 'ARRAY') {
                push @$default_args, map {
                    ("--$dest", $_) 
                } grep { defined $_ } @$value;
            }
            elsif (ref $value eq 'HASH') {
                push @$default_args, map {
                    (my $key = $_) =~ s/=/\\=/g;
                    ("--$dest" => "$key=$value->{$_}")
                } grep {
                    defined $value->{$_}  
                } keys %$value;
            }
            elsif (not ref $value) {
                if (!$spec || $spec eq '!') {
                    push @$default_args, "--$dest" if $value;
                }
                else {
                    push @$default_args, "--$dest", $value if defined $value;
                }
            }
            else {
                $self->{error} = "Invalid default option for $dest";
                $self->{ret} = 0;
            }
            $default_opthash->{$o} = ref $ref ? $ref : \$self->{opt}{$dest};
        }
        $opthash->{$o} = ref $ref ? $ref : \$self->{opt}{$dest};
        $self->{requires}{$dest} = 1 if $opts->{required};
    }

    return if $self->{error};
    if (@$default_args) {
        $self->{ret} = $self->_parse_option($default_args, $default_opthash);
        return unless $self->{ret};
    }

    return $opthash;
}

sub _init_struct {
    my ($self, $struct) = @_;
    $self->{struct} = ref $struct eq 'ARRAY' ? $struct : ref $struct eq 'HASH' ? $self->_normalize_struct($struct) : [];

    if (ref $self->{modes} eq 'ARRAY') {
        my @modeopt;
        for my $m (@{$self->{modes}}) {
            my($mc) = $m =~ /^(\w)/;
            $mc = 'n' if $m eq 'test';
            push @modeopt, [[$mc, $m], qq($m mode)];
        }
        unshift @$struct, @modeopt;
    }

    unshift @{$self->{struct}}, [[qw(h help)], qq(this help message)]
        if $self->{usage} && !$self->_has_option('help');
}

sub _normalize_struct {
    my ($self, $struct) = @_;

    my $result = [];
    for my $option (keys %$struct) {
        my $data = $struct->{$option} || {};
        $data = ref $data eq 'HASH' ? $data : {};
        my $row = [];
        push @$row, [$option, ref $data->{alias} ? @{$data->{alias}} : ()];
        push @$row, $data->{desc};
        push @$row, $data->{type};
        push @$row, $data->{dest};
        push @$row, $data->{opts};
        push @$result, $row;
    }

    return $result;
}

sub _init_summary {
    my ($self, $command_struct) = @_;
    if ($command_struct) {
        for my $key (keys %$command_struct) {
            $self->{summary}{$key} = $command_struct->{$key}->{desc} || '';
        }
    }
    else {
        $self->{summary} = {};
    }
}

sub _extends_usage {
    my ($self, $command_option) = @_;
    for my $key (qw/args other_usage/) {
        $self->{$key} = $command_option->{$key} if exists $command_option->{$key};
    }
}

sub _check_requires {
    my ($self) = @_;
    for my $dest (sort keys %{$self->{requires}}) {
        unless (defined $self->{opt}{$dest}) {
            $self->{ret}   = 0;
            $self->{error} = "`--$dest` option must be specified";
            return 0;
        }
    }
    return 1;
}

sub _option_names {
    my($self, $m) = @_;
    my @sorted = sort {
        my ($la, $lb) = (length($a), length($b));
        return $la <=> $lb if $la < 2 or $lb < 2;
        return 0;
    } ref $m eq 'ARRAY' ? @$m : $m;
    return @sorted;
}

sub _has_option {
    my($self, $option) = @_;
    return 1 if grep { $_ eq $option } map { $self->_option_names($_->[0]) } @{$self->{struct}};
    return 0;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Getopt::Compact::WithCmd - sub-command friendly, like Getopt::Compact

=head1 SYNOPSIS

inside foo.pl:

  use Getopt::Compact::WithCmd;
  
  my $go = Getopt::Compact::WithCmd->new(
     name          => 'foo',
     version       => '0.1',
     args          => 'FILE',
     global_struct => [
        [ [qw/f force/], 'force overwrite', '!', \my $force ],
     ],
     command_struct => {
        get => {
            options     => [
                [ [qw/d dir/], 'dest dir', '=s', undef, { default => '.' } ],
                [ [qw/o output/], 'output file name', '=s', undef, { required => 1 }],
            ],
            desc        => 'get file from url',
            args        => 'url',
            other_usage => 'blah blah blah',
        },
        remove => {
            ...
        }
     },
  );
  
  my $opts = $go->opts;
  my $cmd  = $go->command;
  
  if ($cmd eq 'get') {
      my $url = shift @ARGV;
  }

how will be like this:

  $ ./foo.pl -f get -o bar.html http://example.com/

usage, running the command './foo.pl -x' results in the following output:

  $ ./foo.pl -x
  Unknown option: x
  foo v0.1
  usage: hoge.pl [options] COMMAND FILE
  
  options:
     -h, --help    This help message
     -f, --force   Force overwrite
  
  Implemented commands are:
     get   Get file from url
  
  See 'hoge.pl help COMMAND' for more information on a specific command.

in addition, running the command './foo.pl get' results in the following output:

  $ ./foo.pl get
  `--output` option must be specified
  foo v0.1
  usage: hoge.pl COMMAND [options] url
  
  options:
     -h, --help     This help message
     -d, --dir      Dest dir
     -o, --output   Output file name
  
  blah blah blah

=head1 DESCRIPTION

Getopt::Compact::WithCmd is yet another Getopt::* module.
This module is respected L<Getopt::Compact>.
This module is you can define of git-like option.
In addition, usage can be set at the same time.

=head1 METHODS

=head2 new(%args)

Create an object.
The option most Getopt::Compact compatible.
But I<struct> is cannot use.

The new I<%args> are:

=over

=item C<< global_struct($arrayref) >>

This option is sets common options across commands.
This option value is Getopt::Compact compatible.
In addition, extended to other values can be set.

  use Getopt::Compact::WithCmd;
  my $go = Getopt::Compact::WithCmd->new(
      global_struct => [
          [ $name_spec_arrayref, $description_scalar, $argument_spec_scalar, \$destination_scalar, $opt_hashref ],
          [ ... ]
      ],
  );

And you can also write in hash style.

  use Getopt::Compact::WithCmd;
  my $go = Getopt::Compact::WithCmd->new(
      global_struct => {
          $name_scalar => {
              alias => $name_spec_arrayref,
              desc  => $description_scalar,
              type  => $argument_spec_scalar,
              dest  => \$destination_scalar,
              opts  => $opt_hashref,
          },
          $other_name_scalar => {
              ...
          },
      },
  );

I<$opt_hasref> are:

  {
      default  => $value, # default value
      required => $bool,
  }

=item C<< command_struct($hashref) >>

This option is sets sub-command and options.

  use Getopt::Compact::WithCmd;
  my $go = Getopt::Compact::WithCmd->new(
      command_struct => {
          $command => {
              options        => $options,
              args           => $args,
              desc           => $description,
              other_usage    => $other_usage,
              command_struct => $command_struct,
          },
      },
  );

I<$options>

This value is compatible to C<global_struct>.

I<$args>

command args.

I<$description>

command description.

I<$other_usage>

other usage message.
be added to the end of the usage message.

I<$command_struct>

support nesting.

  use Getopt::Compact::WithCmd;
  my $go = Getopt::Compact::WithCmd->new(
      command_struct => {
          $command => {
              options        => $options,
              args           => $args,
              desc           => $description,
              other_usage    => $other_usage,
              command_struct => {
                  $sub_command => {
                      options => ...
                  },
              },
          },
      },
  );

  # will run cmd:
  $ ./foo.pl $command $sub_command ...

=back

=head2 new_from_array(\@myopts, %args);

C<new_from_array> can be used to parse options from an arbitrary array.

  $go = Getopt::Compact::With->new_from_array(\@myopts, ...);

=head2 opts

Returns a hashref of options keyed by option name.
Return value is merged global options and command options.

=head2 command

Gets sub-command name.

  # inside foo.pl
  use Getopt::Compact::WithCmd;
  
  my $go = Getopt::Compact::WithCmd->new(
     command_struct => {
        bar => {},
     },
  );
  
  print "command: ", $go->command, "\n";
  
  # running the command
  $ ./foo.pl bar
  bar

=head2 commands

Get sub commands. Returned value is ARRAYREF.

  # inside foo.pl
  use Getopt::Compact::WithCmd;
  
  my $go = Getopt::Compact::WithCmd->new(
     command_struct => {
        bar => {
            command_struct => {
                baz => {},
            },
        },
     },
  );
  
  print join(", ", @{$go->commands}), "\n";
  
  # running the command
  $ ./foo.pl bar baz
  bar, baz

=head2 status

This is a true value if the command line was processed successfully. Otherwise it returns a false result.

  $go->status ? "success" : "fail";

=head2 is_success

Alias of C<status>

  $go->is_success # == $go->status

=head2 usage

Gets usage message.

  my $message = $go->usage;
  my $message = $go->usage($target_command_name); # must be implemented command.

=head2 show_usage

Display usage message and exit.

  $go->show_usage;
  $go->show_usage($target_command_name);

=head2 pod2usage

B<Not implemented.>

=head1 AUTHOR

xaicron E<lt>xaicron {at} cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2010 - xaicron

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Getopt::Compact>

=cut
