#!/usr/bin/perl

package TAP::Parser::Iterator::StdOutErr;
use strict;
use warnings;
use vars qw($VERSION @ISA);

use TAP::Parser::Iterator::Process ();
use Config;
use IO::Select;

@ISA = 'TAP::Parser::Iterator::Process';

sub _initialize {
    
    my ( $self, $args ) = @_;
    shift;
    $self->{out}        = shift || die "Need out";
    $self->{err}        = shift || die "Need err";
    $self->{sel}        = IO::Select->new( $self->{out}, $self->{err} );
    $self->{pid}        = shift || die "Need pid";
    $self->{exit}       = undef;
    $self->{chunk_size} = 65536;

    return $self;
}


package TestBed::ParallelRunner;
use SemiModern::Perl;
use TestBed::ParallelRunner::Test;
use TestBed::ForkFramework;
use Data::Dumper;

my $ExperimentTests = [];

my $teste_desc = <<'END';
Not enough arguments to teste
  teste(eid, $ns, $sub, $test_count, $desc);
  teste($pid, $eid, $ns, $sub, $test_count, $desc);
  teste($pid, $gid, $eid, $ns, $sub, $test_count, $desc);
END
      
sub add_experiment { push @$ExperimentTests, TestBed::ParallelRunner::Test::tn(@_); }

sub runtests {
  #prep step
#  say "Prepping";
  my $result = TestBed::ForkFramework::MaxWorkersScheduler::work(4, sub { 
    #return { 'maximum_nodes' => 3};  
    $_[0]->prep 
  }, $ExperimentTests);
  if ($result->[0]) {
    sayd($result->[2]);
    die 'TestBed::ParallelRunner::runtests died during test prep';
  }

  #create schedule step
  my @weighted_experiements;
  for (@{$result->[1]}) {
    push @weighted_experiements, [ $_->[0]->{'maximum_nodes'}, $_->[1] ];
  }
  @weighted_experiements = sort { $a->[0] <=> $b->[0] } @weighted_experiements;

  #count tests step
  my $test_count = 0;
  map { $test_count += $_->test_count } @$ExperimentTests;

#  say "Running";
  reset_test_builder($test_count, no_numbers => 1);
  $result = TestBed::ForkFramework::RateScheduler::work(20, \&tap_wrapper, \@weighted_experiements, $ExperimentTests);
  use Test::Builder;
  my $b = Test::Builder->new;
  $b->current_test($test_count); 
  #sayd($result);
  return;
}

sub reset_test_builder {
  my ($test_count, %options) = @_;
  use Test::Builder;
  my $b = Test::Builder->new;
  $b->reset; 
  $b->use_numbers(0) if $options{no_numbers};
  if ($test_count) { $b->expected_tests($test_count); }
  else { $b->no_plan; }
}

sub setup_test_builder_ouputs {
  my ($out, $err) = @_;
  use Test::Builder;
  my $b = Test::Builder->new;
  $b->output($out);
  $b->fail_output($out);
  $b->todo_output($out);
}

#use Carp;
#$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

our $ENABLE_SUBTESTS_FEATURE = 0;

sub tap_wrapper {
  my ($te) = @_;
  
  if ($ENABLE_SUBTESTS_FEATURE) {
    TestBed::ForkFramework::Scheduler->redir_std_fork( sub {
      my ($in, $out, $err, $pid) = @_;
      #while(<$out>) { print "K2" . $_; }
      use TAP::Parser;  
      my $tapp = TAP::Parser->new({'stream' => TAP::Parser::Iterator::StdOutErr->new($out, $err, $pid)});
      while ( defined( my $result = $tapp->next ) ) {
        #sayd($result);
      }
      ok(1, $te->desc) if $ENABLE_SUBTESTS_FEATURE && $tapp;
    },
    sub {
      reset_test_builder($te->test_count) if $ENABLE_SUBTESTS_FEATURE;
      setup_test_builder_ouputs(*STDOUT, *STDERR);
      $te->run_ensure_kill;
    });
  }
  else {
    $te->run_ensure_kill;
  }
  return 0;
}

1;
