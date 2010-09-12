package Getopt::Compact::WithCmd;

use strict;
use warnings;
use 5.008_001;
use base 'Getopt::Compact';
use Getopt::Long qw/GetOptionsFromArray/;
use constant DEFAULT_CONFIG => (no_auto_abbrev => 1, bundling => 1);

our $VERSION = '0.01';

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        cmd      => $args{cmd} || do { require File::Basename; File::Basename::basename($0) },
        name     => $args{name},
        version  => $args{version} || $::VERSION,
        modes    => $args{modes},
        opts     => {},
        usage    => exists $args{usage} && !$args{usage} ? 0 : 1,
        args     => $args{args} || '',
        struct   => [],
        summary  => {},
        requires => {},
        error    => undef,
        ex_usage => '',
    }, $class;

    my %config = (DEFAULT_CONFIG, %{$args{configure} || {}});
    my @gconf = grep $config{$_}, keys %config;
    Getopt::Long::Configure(@gconf) if @gconf;

    if (my $command_struct = $args{command_struct}) {
        for my $key (keys %$command_struct) {
            $self->{summary}{$key} = ucfirst($command_struct->{$key}->{desc} || '');
        }
    }

    if (my $global_struct = $args{global_struct}) {
        $self->_init_struct($global_struct);
        my $opthash = $self->_parse_struct;

        my @gopts;
        while (@ARGV) {
            last unless $ARGV[0] =~ /^-/;
            push @gopts, shift @ARGV;
        }

        if (@gopts) {
            $self->{ret} = GetOptionsFromArray(\@gopts, %$opthash);
            return $self unless $self->{ret};
        }
        return $self unless $self->_check_requires;
    }

    my $command_struct = $args{command_struct} || {};
    my $command_map = { map { $_ => 1 } keys %$command_struct };
    my $command = shift @ARGV;
    unless ($command) {
        $self->{ret} = 1;
        return $self;
    }
    unless ($command_map->{$command}) {
        $self->{error} = "Unknown command: $command";
        $self->{ret} = 0;
        return $self;
    }

    $self->{command} = $command;
    $self->_init_struct($command_struct->{$command}->{options});
    $self->{args} = $command_struct->{$command}{args} if exists $command_struct->{$command}{args};
    my $opthash = $self->_parse_struct;
    $self->{ret} = GetOptionsFromArray(\@ARGV, %$opthash);
    $self->_check_requires;
    
    return $self;
}

sub command    { $_[0]->{command} }
sub is_success { $_[0]->status    }

sub usage {
    my($self) = @_;
    my $usage = "";
    my($v, @help, @commands);

    my($name, $version, $cmd, $struct, $args, $summary, $error) = map
        $self->{$_} || '', qw/name version cmd struct args summary error/;

    $usage .= "$error\n" if defined $error;

    if($name) {
        $usage .= $name;
        $usage .= " v$version" if $version;
        $usage .= "\n";
    }
    
    if ($self->command) {
        $usage .= "usage: $cmd COMMAND [options] $args\n\n";
    }
    else {
        $usage .= "usage: $cmd [options] COMMAND $args\n\n";
    }

    my $indent = '   ';
    for my $o (@$struct) {
        my($opts, $desc) = @$o;
        next unless defined $desc;
        my @onames = $self->_option_names($opts);
        my $optname = join
            (', ', map { (length($_) > 1 ? '--' : '-').$_ } @onames);
        $optname = "    ".$optname unless length($onames[0]) == 1;
        push @help, [ $indent, $optname, ucfirst($desc) ];
    }

    require Text::Table;
    my $sep = '   ';
    $usage .= 'options:';
    $usage .= Text::Table->new(' ', '', \$sep, '')->load(@help)->stringify."\n";

    unless ($self->command) {
        for my $command (sort keys %$summary) {
            push @commands, [ $indent, $command, $summary->{$command} ];
        }

        $usage .= 'Implemented commands are:';
        $usage .= Text::Table->new(' ', ' ', \$sep, '')->load(@commands)->stringify."\n";
        $usage .= "See '$cmd COMMAND --help' for more information on a specific command.\n";
    }

    return $usage;
}

sub show_usage {
    my ($self) = @_;
    print $self->usage;
    exit !$self->{ret};
}

sub _parse_struct {
    my ($self) = @_;
    my $struct = $self->{struct};
    
    my $opthash = {};
    for my $s (@$struct) {
        my($m, $descr, $spec, $ref, $opts) = @$s;
        my @onames = $self->_option_names($m);
        my($longname) = grep length($_) > 1, @onames;
        my $o = join('|', @onames).($spec || '');
        my $dest = $longname ? $longname : $onames[0];
        $opts ||= {};
        $self->{opt}{$dest} = exists $opts->{default} ? $opts->{default} : undef;
        if (ref $ref) {
            my $value = delete $self->{opt}{$dest};
            $$ref = $value if ref $ref && defined $value;
        }
        $opthash->{$o} = ref $ref ? $ref : \$self->{opt}{$dest};
        $self->{requires}{$dest} = 1 if $opts->{required};
    }
    return $opthash;
}

sub _init_struct {
    my ($self, $struct) = @_;
    $self->{struct} = $struct || [];

    if ($self->{modes}) {
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

    unless($self->_has_option('man')) {
        push @{$self->{struct}}, ['man', qq(Display documentation)];
        $self->{_allow_man} = 1;
    }
}

sub _check_requires {
    my ($self) = @_;
    for my $dest (sort keys %{$self->{requires}}) {
        unless (defined $self->{opt}{$dest}) {
            $self->{ret}   = 0;
            $self->{error} = "`--$dest` option must be specified";
            return;
        }
    }
    return 1;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Getopt::Compact::WithCmd -

=head1 SYNOPSIS

  use Getopt::Compact::WithCmd;

=head1 DESCRIPTION

Getopt::Compact::WithCmd is

=head1 AUTHOR

xaicron E<lt>xaicron {at} cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2010 - xaicron

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
