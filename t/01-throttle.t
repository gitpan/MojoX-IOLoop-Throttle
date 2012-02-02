#!/usr/bin/env perl

use Test::More tests => 18;

my $CLASS;

BEGIN {

  #$ENV{MOJO_THROTTLE_DEBUG} = 1;
  #$ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
  $CLASS = 'MojoX::IOLoop::Throttle';
  use_ok $CLASS;
}

CROAK: {
  eval { $CLASS->new->throttle()->throttle() };
  like $@, qr/running/, 'Calling throttle twice without stopping does croak';
  isa_ok $CLASS->new->throttle()->drop()->throttle(), $CLASS;
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
$t_destroy->throttle(limit_period => 1);
$t_destroy->DESTROY();


# Stopping
my $t_stop_flag;
my $t_stop = $CLASS->new();

$t_stop->on(cb => sub { $t_stop_flag++; shift->drop() });
$t_stop->throttle();


# 'limit_period', 'period' event and 'cb' arg in one test! all or nothing
my $lp_flag;
my $lp_count;
my $t_lp = $CLASS->new();

$t_lp->throttle(
  limit_period => 2,
  period       => 0.3 * $SCALE,
  cb           => sub { $lp_flag++ }
);
$t_lp->on(period => sub { $lp_count++ });


# limit_run and 'end' event
my $lr_flag;
my $lr = $CLASS->new();

$lr->throttle(
  limit_run => 4,
  period    => 0.001,
  cb        => sub {
    my ($thr) = @_;
    $lr_flag++;
    $thr->ioloop->timer(0.3 * $SCALE => sub { $thr->end; });
  }
);


# drain event
my $drain_flag;
my $t_drain = $CLASS->new()->throttle(
  limit_period => 1,
  cb           => sub { shift->end }
);
$t_drain->on(drain => sub { $drain_flag++ });


# Здесь мы забыли сделать end. А значит drain не вызовется никогда
my $drain_flag2;
my $t_drain2 = $CLASS->new()->throttle(limit_period => 1, cb => sub { });
$t_drain2->on(drain => sub { $drain_flag2++ });


# Если нет коллбека, сервер должен быть остановлен после вызова
my $running_flag;
my $t_running = $CLASS->new()->throttle(limit_period => 1);
$t_running->ioloop->timer(
  0.1 => sub { $running_flag = $t_running->{is_running} });


# finish event
my ($finish_count, $finish_flag);
my $t_finish = $CLASS->new()->throttle(
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
);
$t_finish->on(finish => sub { $finish_flag++ });


# no finish without ->end
my ($nfinish_flag);
my $t_nfinish = $CLASS->new()->throttle(limit => 2, cb => sub {;});
$t_nfinish->on(finish => sub { $nfinish_flag++ });

#autodrop
my $autodrop_flag;
my $dropped = $CLASS->new(autodrop => 0)->throttle(limit_run => 2, cb => sub { $autodrop_flag++ });
$dropped->DESTROY;




diag
  "Starting loop for a $SCALE seconds (depends on your perfomance).\nPlease, wait...";

# Start loop for $SCALE seconds.
$ioloop->timer(1 * $SCALE => sub { $ioloop->stop() });
$ioloop->start;

# --------------------------- start ------------------------------------
# Now let's see wtf (actually, the most of our tests starts right now)?

is $t_destroy_flag, undef, 'DESTROY stops timers by default!';
is $t_stop_flag,    1,     'stop method works great!';
is $lp_count, 3, 'Ok, period 0.3 have a time to refresh 3 times in 1 second';
is $lp_flag, ($lp_count + 1) * 2,
  'Ok, we have increased the flag for 8 times with limit_period => 2 and period => 0.3s';
is $lr_flag, (int(1 / 0.3) + 1) * 4, "limit_run works!";
ok $drain_flag > 1,
    "Drain event: "
  . int($drain_flag / $SCALE)
  . "/s; This is your IOWatcher's \"drain\" event perfomance. Set MOJO_IOWATCHER enviropment to change default one. (Mojo::IOWather::EV is much faster than Mojo::IOWather)";
is $drain_flag2,  undef, 'Ok, drain works with ->end(s) only';
is $running_flag, undef, 'Without cb\'s subscribers throttle drops itself';
is $finish_count, 2,     "limit works!";
is $finish_flag,  1,     "Finish event emitted successfully";
is $nfinish_flag, undef, 'No finish event without ->end(s)';
is $autodrop_flag, 2, 'Ok, autodrop works';

# ---------------------------- end ----------------------------------------

# И на последочек смотрим как ведет себя дракоша в общем, не мешает ли другим таймерам
# wait method it global ioloop loop
my ($wait_flag1, $wait_flag2);
my $t_wait = $CLASS->new();

# Первое сработает, а второе не должно успеть
$ioloop->timer(0.01 * $SCALE => sub { $wait_flag1++; });
$ioloop->timer(0.15 * $SCALE + 0.1 => sub { $wait_flag2++; $_[0]->stop; });

# Тут throttle наш луп хуюп
$t_wait->throttle(
  limit => 1,
  delay => 0.05 * $SCALE,
  cb    => sub { $_[0]->end; }
);
$t_wait->wait;

is $wait_flag1, 1,     "wait method does not drops ioloop timers";
is $wait_flag2, undef, "and stop loop succesfully";

# Но все таки таймер в 1 * $SCALE секунд остался, и должен сработать щас
$ioloop->start();
is $wait_flag2, 1, 'ok, our other timers are alive';
