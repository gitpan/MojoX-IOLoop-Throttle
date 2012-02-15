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

use Mojo::IOLoop;
my $ioloop = Mojo::IOLoop->singleton;

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

# DESTROING
my $t_destroy_flag;
my $t_destroy = $CLASS->new();

$t_destroy->on(cb => sub { $t_destroy_flag = 'fuck'; });
$t_destroy->run();

# call $t_destroy->DESTROY();
undef $t_destroy;

# 2 Dropping
my $t_drop_flag;
my $t_drop = $CLASS->new();

$t_drop->on(cb => sub { $t_drop_flag++; shift->drop() });
$t_drop->run();

# 3 'limit_period', 'period' event and 'cb' arg in one test! all or nothing
my $lp_flag;
my $lp_count;
my $t_lp = $CLASS->new(
  limit_period => 2,
  period       => 0.3 * $SCALE,
);
$ioloop->timer(0.8 * $SCALE => sub { $t_lp->drop });
$t_lp->run(sub { $lp_flag++ });
$t_lp->on(period => sub { $lp_count++ });


# 4 limit_run and 'end' event
my $lr_flag;
my $lr = $CLASS->new(limit_run => 3);
$ioloop->timer(0.5 * $SCALE => sub { $lr->drop });
$lr->run(
  sub {
    my ($thr) = @_;
    $lr_flag++;
    $ioloop->timer(0.2 * $SCALE => sub { $thr->end; });
  }
);

# 5 drain event
my $drain_flag;
my $t_drain = $CLASS->new(limit_period => 1)->run(sub { shift->end });
$t_drain->on(drain => sub { $drain_flag++ });


# 6 Здесь мы забыли сделать end. А значит drain не вызовется никогда
my $drain_flag2;
my $t_drain2 = $CLASS->new(limit_period => 1, cb => sub { })->run();
$t_drain2->on(drain => sub { $drain_flag2++ });

# 7 finish event
my ($finish_count, $finish_flag);
my $t_finish = $CLASS->new(limit => 2)->run(
  sub {
    my ($t) = @_;
    $ioloop->timer(
      0.1 * $SCALE => sub {
        $finish_count++;
        $t->end();
      }
    );
  }
);
$t_finish->on(finish => sub { $finish_flag++ });

# 8 no finish without ->end
my ($nfinish_flag);
my $t_nfinish = $CLASS->new(cb => sub {;})->run();
$t_nfinish->on(finish => sub { $nfinish_flag++ });


# 9 start twice (nothing with carp)
my ($t9_count, $t9_carp);
my $t9 = $CLASS->new(limit_period => 1);
$t9->run(sub { $t9_count++ });
$t9->period(0.1 * $SCALE);
CARP: {
  local $SIG{__WARN__} = sub {
    $t9_carp = shift;
  };
  $t9->run(sub {;});
}

# 12 autostop
# stops timers on limit (but do not drop object because we need on finish event)
# no on drain, on cb or on_period here, autostop = 1 by default
my ($t12, $t12_dr_flag, $t12_cb_flag, $t12_pe_flag);
$t12 = $CLASS->new(limit => 1, period => 0.1 * $SCALE);
$t12->run(
  sub {
    my $self = shift;
    $self->on(drain  => sub { $t12_dr_flag++ });
    $self->on(period => sub { $t12_pe_flag++ });
    $self->on(cb     => sub { $t12_cb_flag++ });
    $self->end;
  }
);

# autostop = 0, all events except cb are emitted
my ($t12_2, $t12_dr_flag_2, $t12_cb_flag_2, $t12_pe_flag_2);
$t12_2 = $CLASS->new(limit => 1, period => 0.1 * $SCALE);
$t12_2->autostop(0);
$t12_2->run(
  sub {
    my $self = shift;
    $self->on(drain  => sub { $t12_dr_flag_2++ });
    $self->on(period => sub { $t12_pe_flag_2++ });
    $self->on(cb     => sub { $t12_cb_flag_2++ });
    $self->end;
  }
);

# 13
# add limit after stopping end resume
# вызовется событие on finish, остановит, но подписчики никуда не денутся
my ($t13, $t13_flag);
$t13 = $CLASS->new(limit => 1);

$t13->autostop(0);
$t13->run(sub { $t13_flag++; });
$t13->on(cb => sub { shift->end });


# Пробуем повторить попытку, добавив лимит 2, потом добавим лимит 1.
# это должно разморозить нас так как autostop не включен
$ioloop->timer(
  0.2 * $SCALE => sub {
    $t13->add_limit(2) if $t13->is_running;
  }
);

$ioloop->timer(
  0.5 * $SCALE => sub {
    # А это добавит 1 по умолчанию
    $t13->add_limit if $t13->is_running;
  }
);



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
is $t_drop_flag, 1, 'stop method works great!';

# 3
is $lp_count, 2,
  "Ok, period 0.3 * $SCALE have a time to refresh 3 times in 0.8 * $SCALE second";

is $lp_flag, ($lp_count + 1) * 2,
  'Ok, we have increased the flag for 8 times with limit_period => 2 and period => 0.3s';

# 4
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
like $t9_carp, qr/already running/i,
  'Ok, run on running throttle call carp and change nothing';


is $t12_dr_flag || $t12_cb_flag || $t12_pe_flag, undef,
  "autostop stop all timers. no events emitted after limit exhausted";
is $t12->is_running, undef;

ok $t12_dr_flag_2 && $t12_pe_flag_2 && !$t12_cb_flag_2,
  "if autostop = false, period and drain event still runs after limit is exhausted";

is $t13_flag, 4, "add_limit works as expected with autodrop = 0";


