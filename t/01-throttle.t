#!/usr/bin/env perl
use strict;
use warnings;

use Test::More 'no_plan';

my $CLASS;

BEGIN {

  #$ENV{MOJO_THROTTLE_DEBUG} = 1;
  #$ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
  $CLASS = 'MojoX::IOLoop::Throttle';
  use_ok $CLASS;
}


my $ioloop = $CLASS->new()->ioloop;

# TODO: make better calculations
my $SCALE;
SCALE: {
  unless ($SCALE = $ENV{THROTTLE_SCALE}) {

	# Определяем производительность, необходимую чтобы выполнить тесты побыстрее
	my $count;
	my $id = $ioloop->recurring(0.001 => sub { $count++ });
	$ioloop->timer(0.2 => sub { $ioloop->drop($id); $ioloop->stop(); });
	$ioloop->start();
	$SCALE = int(30 / $count * 10) / 10;

	# For fast computers
	$SCALE = 0.4 if $SCALE < 0.4;

	diag "Your ${\ref( $ioloop->iowatcher)} perfomance is $count/0.2 sec. "
	  . "We will start the loop for test for $SCALE seconds\n. "
	  . "You can pass a new value to the THROTTLE_SCALE enviropment variable";
  }
}


# Все эти тесты будут выполнены одновременно за 1*$SCALE секунд (параллельно),
# а результат потом сравним. Иначе мы б охренели ждать и расфигарили что-нить ценное

# DESTROING, autodrop is true by defaults
my $t_destroy_flag;
my $t_destroy = $CLASS->new();

$t_destroy->on(cb => sub { $t_destroy_flag = 'fuck' });
$t_destroy->run();
$t_destroy->DESTROY();

# 2 Stopping
my $t_stop_flag;
my $t_stop = $CLASS->new();

$t_stop->on(cb => sub { $t_stop_flag++; shift->drop() });
$t_stop->run();

# 3 'limit_period', 'period' event and 'cb' arg in one test! all or nothing
my $lp_flag;
my $lp_count;
my $t_lp = $CLASS->new(
  limit_period => 2,
  period       => 0.3 * $SCALE,
  cb           => sub { $lp_flag++ }
);
$t_lp->ioloop->timer(0.8 * $SCALE => sub { $t_lp->drop });
$t_lp->run();
$t_lp->on(period => sub { $lp_count++ });


# 4 limit_run and 'end' event
my $lr_flag;
my $lr = $CLASS->new(
  limit_run => 3,
  cb        => sub {
	my ($thr) = @_;
	$lr_flag++;
	$thr->ioloop->timer(0.2 * $SCALE => sub { $thr->end; });
  }
);
$lr->ioloop->timer(0.5 * $SCALE => sub {$lr->drop} );
$lr->run();

# 5 drain event
my $drain_flag;
my $t_drain = $CLASS->new(
  limit_period => 1,
  cb           => sub { shift->end }
  )->run(

  );
$t_drain->on(drain => sub { $drain_flag++ });


# 6 Здесь мы забыли сделать end. А значит drain не вызовется никогда
my $drain_flag2;
my $t_drain2 = $CLASS->new(limit_period => 1, cb => sub { })->run();
$t_drain2->on(drain => sub { $drain_flag2++ });

# 7 finish event
my ($finish_count, $finish_flag);
my $t_finish = $CLASS->new(
  limit => 2,
  cb    => sub {
	my ($t) = @_;
	$t->ioloop->timer(
	  0.1 * $SCALE => sub {
		$finish_count++;
		$t->end();
	  }
	);
  }
)->run();
$t_finish->on(finish => sub { $finish_flag++ });

# 8 no finish without ->end
my ($nfinish_flag);
my $t_nfinish = $CLASS->new(cb => sub {;})->run();
$t_nfinish->on(finish => sub { $nfinish_flag++ });


# 9 start twice (nothing)
my $t9_count;
my $t9 = $CLASS->new(limit_period => 1, cb => sub { $t9_count++ });
$t9->run();
$t9->period(0.1 * $SCALE);
$t9->run();


# 10 stop,start with saving period timers
my $t10_count;
my $t10 = $CLASS->new(
  limit_period => 2,
  period       => 0.3 * $SCALE,
  cb           => sub { $t10_count++ }
);
$t10->ioloop->timer(0.01 * $SCALE => sub { $t10->run() });
$t10->ioloop->timer(0.1 * $SCALE  => sub { $t10->stop() });
$t10->ioloop->timer(0.2 * $SCALE  => sub { $t10->run() });
$t10->ioloop->timer(0.5 * $SCALE  => sub { $t10->drop });


# 11
my $t11_count;
my $t11 = $CLASS->new(cb => sub { $t11_count++ });
$t11->begin;
$t11->begin(2);

diag
  "Starting loop for a $SCALE seconds (depends on your perfomance).\nPlease, wait...";

# Start loop for $SCALE seconds.
$ioloop->timer(1 * $SCALE => sub { $ioloop->stop() });
$ioloop->start;

# --------------------------- start ------------------------------------
# Now let's see wtf (actually, the most of our tests starts right now)?

# 1
is $t_destroy_flag, undef, 'DESTROY stops timers by default!';

# 2
is $t_stop_flag, 1, 'stop method works great!';

# 3
is $lp_count, 2,
  "Ok, period 0.3 * $SCALE have a time to refresh 3 times in 0.8 * $SCALE second";

#4
is $lp_flag, ($lp_count + 1) * 2,
  'Ok, we have increased the flag for 8 times with limit_period => 2 and period => 0.3s';

is $lr_flag, (int(0.5 / 0.2) + 1) * 3, "limit_run works!";

# 5
ok $drain_flag > 1,
	"Drain event: "
  . int($drain_flag / $SCALE)
  . "/s; This is your IOWatcher's \"drain\" event perfomance. Set MOJO_IOWATCHER enviropment to change default one. (Mojo::IOWather::EV is much faster than Mojo::IOWather)";

# 6
is $drain_flag2, undef, 'Ok, drain works with ->end(s) only';


# 7
is $finish_count, 2, "limit works!";
is $finish_flag,  1, "Finish event emitted successfully";

# 8
is $nfinish_flag, undef, 'No finish event without ->end(s)';

# 9
is $t9_count, 1, 'ok, run on running throttle do nothing';

# 10
is $t10_count, 4, 'ok. Stop/start works and save period';

is $t11_count, 3, 'Ok, begin method works';

# ---------------------------- end ----------------------------------------

# И на последочек смотрим как ведет себя дракоша в общем, не мешает ли другим таймерам
# wait method it global ioloop loop
my ($wait_flag1, $wait_flag2);
my $t_wait = $CLASS->new();

# Первое сработает, а второе не должно успеть
$ioloop->timer(0.01 * $SCALE => sub { $wait_flag1++; });
$ioloop->timer(0.15 * $SCALE + 0.1 => sub { $wait_flag2++; $_[0]->stop; });


