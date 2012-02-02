#!/usr/bin/env perl
use Mojo::Base -strict;
use MojoX::IOLoop::Throttle;

=head1 Description

Find registrars for a list of domains (only .ru) via whois.ripn.net 
in parallels with some limitations.
=cut

#BEGIN { $ENV{MOJO_THROTTLE_DEBUG} = 1 }
#BEGIN { $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher'; }


$| = 1;
my @domains = read_domains();

# WHOIS params
my %PARAMS = (port => '43', address => 'whois.ripn.net');
my $RE = qr/registrar:\s*([A-Z0-9-]+)/;

# Our CallBack
my $cb = sub {
  my ($thr) = @_;
  my $domain = shift @domains;
  say "[info] Starting query for $domain";

  my $text;
  my $id = Mojo::IOLoop->client(
    \%PARAMS => sub {
      my ($loop, $err, $stream) = @_;
      if ($err) {
        warn "Error processing $domain: $err\n";
        $thr->end;
      }
      $stream->on(read => sub { $text .= $_[1] });
      $stream->on(
        close => sub {
          $text =~ $RE;
          say "\nGOT $domain: " . ($1 || " domain is free") . "\n";
          $thr->end();
        }
      );

      $stream->write("$domain\n");
    }
  );
};


# Throttle
my $throttle = MojoX::IOLoop::Throttle->new();

my $cb_text =          "[info] I am a job. I have increased our running count (for run_limit).";
my $drain_once_text =  "\nOoops! limit_period is exhausted. Waiting for the next period";
my $period_text =      "\n[info] Next period. I have dropped a counter for period_limit. But as about limit_run counter - it's not my business";


# Events
$throttle->on(cb     => sub { say $cb_text});
$throttle->on(finish => sub { say "Finish!!!!!!!!" });
$throttle->on(drain  => sub { print "." });
$throttle->on(period => sub { say $period_text });
$throttle->once(drain => sub {$drain_once_text});


# Throttle!
$throttle->throttle(
  limit => scalar @domains,     # Play [total number] jobs(callbacks)
  limit_run => 2,               # But allow not more than 3 running (parallel,incomplete) jobs

  period       => 2,            # 10 seconds
  limit_period => 4,            # do not start more then 5 jobs per 10 seconds "period"

  #delay => 0.1,                # simulate (or not) a little latency between shots (timer resolution)
  cb => $cb,                    # play this callback
);

# Let's start
$throttle->wait;

exit 0;


# -------------------------- Foo --------------

sub read_domains {
  say
    "Type domain list(ru only). Type empty line or EOF(CTRL+D) to start my job";

  # Fill our domain list
  my @domains;
  while (my $domain = STDIN->getline) {
    chomp($domain);
    last unless $domain;

    if ($domain =~ /([-a-z0-9]{2,63}.ru)/i) {
      push @domains, $1;
    }
    else {
      warn "Input a valid .ru domain name. Example: yandex.ru\n";
    }
  }

  die "Got an empty list" unless scalar @domains;
  return @domains;
}
