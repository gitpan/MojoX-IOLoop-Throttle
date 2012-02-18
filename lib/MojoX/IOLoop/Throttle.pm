package MojoX::IOLoop::Throttle;
use Mojo::Base 'Mojo::EventEmitter';

our $VERSION = '0.01_23';
$VERSION = eval $VERSION;


use Mojo::IOLoop;
use Carp qw/croak carp/;
use Scalar::Util 'weaken';

my $DEBUG = $ENV{MOJO_THROTTLE_DEBUG};

has iowatcher => sub { Mojo::IOLoop->singleton->iowatcher };

has [qw/is_running /];

has [qw/ period limit_period limit_run limit/] => 0;

has delay => '0.0001';

has autostop => 1;


sub run {
  my ($self, $cb, @params) = @_;

  #croak unless $cb;
  # Инициализируем стандартными значениями
  $self->period;
  $self->limit_period;
  $self->limit_run;
  $self->limit;


  # Check if we are already running
  if ($self->{is_running}++) {
    carp "I am already running. Just return";
    return;
  }
  warn "Starting new $self\n" if $DEBUG;


  # defaults
  my $iowatcher = $self->iowatcher;
  $self->{count_period} ||= 0;
  $self->{count_run}    ||= 0;
  $self->{count_total}  ||= 0;

  weaken $self;

  if ($self->period && !$self->{period_timer_id}) {
    $self->{period_timer_id} =
      $iowatcher->recurring($self->period =>
        sub { $self->{count_period} = 0; $self->emit('period'); });
  }

  $self->{cb_timer_id} = $iowatcher->recurring(
    $self->delay => sub {


      unless (!$self->{limit} || $self->{count_total} < $self->{limit}) {
        warn
          "The limit $self->{limit} is exhausted and autodrop not setted. Emitting drain\n"
          if $DEBUG;
        $self->emit('drain');


        return;
      }

      # Проверяем душить или нет. Нужно чтобы был задан хотя бы один из параметров limit or limit_run, без этого будет drain
      my $cond = (

        # Не вышли за пределы лимита или лимит не задан, но задан хотя бы limit_run
        ( $self->{count_period} < $self->{limit_period}
            || (!$self->{limit_period})
        )

        # Не вышли за пределы работающих параллельно задач или если такого лимита нет, то задан хотя бы limit
          && (($self->{count_run} < $self->{limit_run})
          || (!$self->{limit_run}))
      );

      if ($cond) {
        #$self->{count_period}++;
        #$self->{count_run}++;
        #$self->{count_total}++;

        $cb->($self, @params);

        return;

      }

      # Если вышли за пределы лимита в периоде и нет запущенных коллбэков
      elsif (!$self->{count_run}) {
        $self->emit('drain');
        return;
      }

      # Если здесь, значит у нас лимиты
      return;
    }
  );
  return $self;

}

# Сообщить что мы начали
sub begin {
  my $self = shift;
  $self->{count_period}++;
  $self->{count_run}++;
  $self->{count_total}++;
  return;
}

# Сообщить что мы закончили
sub end {
  my ($self) = @_;
  $self->{count_run}--;

  # Вызвали end не оттуда и произошел рассинхрон, что критично
  if ($DEBUG) { warn "Not running but ended" unless $self->is_running }
  return unless $self->is_running;

  # Если исчерпан лимит
  if (  (!$self->{count_run})
    and $self->{limit}
    and $self->{count_total} >= $self->{limit})
  {
    warn "finish event\n" if $DEBUG;
    $self->emit('finish');

  }
  return;
}


sub DESTROY {
  my ($self) = @_;
  warn "Destroing $self\n" if $DEBUG;

  $self->drop();
  $self->SUPER::DESTROY() if $self->can("SUPER::DESTROY");
  return;
}

# Сразу останавливает и все обнуляет
sub drop {
  my ($self) = @_;

  warn "Dropping $self ...\n" if $DEBUG;
  
  # Clear my timers
  if (my $iowatcher = $self->iowatcher) {
    warn "Stopping(Dropping timers)\n"         if $DEBUG;
    $iowatcher->drop($self->{cb_timer_id})     if $self->{cb_timer_id};
    $iowatcher->drop($self->{period_timer_id}) if $self->{period_timer_id};
  }


  foreach (keys %$self) {
    delete $self->{$_};
  }

  return $self;
}



# Увеличивает общий лимит на 1 или $count раз, если $count указан в качестве второго аргумента
# запускает (если еще не запущен, пытается в общем) сделать $self->run
sub add_limit {
  my ($self, $count) = @_;
  $count ||= 1;
  $self->{limit} += $count;
  return $self;
}


1;

=head1 NAME

MojoX::IOLoop::Throttle - throttle Mojo events 

=head1 VERSION

Version 0.01_23. (DEV)

=cut


=head1 SYNOPSIS
  
    #!/usr/bin/env perl
  use Mojo::Base -strict;
  use MojoX::IOLoop::Throttle;
  $| = 1;

  # New throttle object
  my $throttle = MojoX::IOLoop::Throttle->new(
    limit_run =>
      3,  # Allow not more than [limit_run] running (parallel,incomplete) jobs

    period => 2,    # seconds
    limit_period =>
      4,    # do not start more than [limit_period] jobs per [period] seconds

    delay => 0.05    # Simulate a little latency
  );

  my $count;

  # Subscribe to finish event
  $throttle->on(finish =>
      sub { say "I've processed $count jobs! Bye-bye"; Mojo::IOLoop->stop; });

  # Throttle 20 jobs!
  $throttle->limit(20);


  # CallBack to throttle
  $throttle->run(
    sub {
      my ($thr) = @_;

      # We a beginning one job
      $thr->begin;

      my $rand_time = rand() / 5;
      say "Job $rand_time started";
      $thr->iowatcher->timer(
        $rand_time => sub {
          say "job $rand_time ended";
          $count++;

          # Say that we end (to decrease limit_run count and let other job to start)
          $thr->end();
        }
      );
    }
  );

  # Let's start
  Mojo::IOLoop->start;







=head1 DESCRIPTION

  AHTUNG!!!

  This is a very first development release. Be patient. Documentation is in progress.
  You can find some working real-life examples in 'example' dir.
  
  If your are going to use this module now, use subclassing, because all method and options are experimental


=head1 OBJECT METHODS

=head2 C<begin>

Say that the job was started

=head2 C<end>

Say that the job was ended


=head2 C<drop>

Drop timers, counters and events

=head2 C<add_limit>
  
  $thr->add_limit($n);
  
Increase a limit attr. If agrument is omitter, increase on 1

=head2 C<run>

  $thr->run(sub {...});
  
  Starts doing job

=head1 ATTRIBUTES

=head2 C<limit>
  
=head2 C<limit_run>

=head2 C<limit_period>

=head2 C<period>

=head2 C<delay>


  
  
=head1 AUTHOR

Alex, C<< <alexbyk at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-mojox-ioloop-throttle at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=MojoX-IOLoop-Throttle>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc MojoX::IOLoop::Throttle


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=MojoX-IOLoop-Throttle>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/MojoX-IOLoop-Throttle>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/MojoX-IOLoop-Throttle>

=item * Search CPAN

L<http://search.cpan.org/dist/MojoX-IOLoop-Throttle/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Alex.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of MojoX::IOLoop::Throttle
