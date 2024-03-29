#!/usr/bin/env perl
use Mojo::Base -strict;
use MojoX::IOLoop::Throttle 0.0117;

=head1 Description

Find registrars for a list of domains (only .ru) via whois.ripn.net 
in parallels with some limitations.

Сделать запрос к whois.ripn.net и найти регистратора для списка доменов параллельно
и с ограничениями:
- Пытается запустить не больше 4 запросов за 2 секунду. Если успели выполнить
  4 запроса раньше и они завершились вызовом end, вызывается событие 'drain' до следующего периода
- Не позволяет запускать что-либо, если 2 запроса не успели окончится. То бишь
  не позволяет сделать более 2 "открытых соединений".
- После того, как выполнятся все запросы и последний из них вызовет ->end,
  вызывает событие 'finish'


Cмотрите строки 71-101, остальное можно пропустить

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
  $thr->begin;

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


my $throttle = MojoX::IOLoop::Throttle->new(

  # Allow not more than [limit_run] running (parallel,incomplete) jobs
  limit_run => 2,

  # do not start more then [limit_period] jobs per [period] seconds
  period       => 2,
  limit_period => 4,

  # you can simulate a little latency between shots (timer resolution)
  #delay => 0.1,
);


my $drain_once_text =
  "\nOoops! limit_period or limit is exhausted. Waiting for the next period or finish";
my $period_text =
  "\n[info] Next period. I have dropped a counter for period_limit. But as about limit_run counter - it's not my business";


$throttle->on(finish => sub { say "Finish!!!!!!!!"; Mojo::IOLoop->stop; });
$throttle->on(drain  => sub { print "." });
$throttle->on(period => sub { say $period_text });
$throttle->once(drain => sub { say $drain_once_text });

# Play n jobs (run throttle for n times)
$throttle->limit(scalar @domains);

# Let's start
$throttle->run(cb => $cb);
Mojo::IOLoop->start;

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
