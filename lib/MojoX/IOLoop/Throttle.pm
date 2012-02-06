package MojoX::IOLoop::Throttle;
use Mojo::Base 'Mojo::EventEmitter';

our $VERSION = '0.01_11';
$VERSION = eval $VERSION;


use Mojo::IOLoop;
use Carp 'croak';

my $DEBUG = $ENV{MOJO_THROTTLE_DEBUG};

has ioloop => sub { Mojo::IOLoop->singleton };

has [qw/is_running is_running/];

has [qw/ period limit_period limit_run limit/] => 0;

has delay => '0.0001';

has 'cb';


sub run {
  my ($self, %args) = @_;

  # Инициализируем стандартными значениями
  $self->period;
  $self->limit_period;
  $self->limit_run;
  $self->limit;


  # Check if we are already running
  return if $self->{is_running}++;
  warn "Starting new $self\n" if $DEBUG;
  

  # defaults
  my $ioloop = $self->ioloop;
  $self->{count_period} ||= 0;
  $self->{count_run}    ||= 0;
  $self->{count_total}  ||= 0;

  if ($self->{period} and !$self->{period_timer_id}) {
	$self->{period_timer_id} =
	  $ioloop->recurring($self->{period} =>
		sub { $self->{count_period} = 0; $self->emit('period'); });
  }

  $self->{cb_timer_id} = $ioloop->recurring(
	$self->{delay} => sub {


	  unless (!$self->{limit} || $self->{count_total} < $self->{limit}) {
		warn "The limit $self->{limit} is exhausted. Emitting drain\n" if $DEBUG;
		$self->emit('drain');
		#$self->drop;
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
		$self->{count_period}++;
		$self->{count_run}++;
		$self->{count_total}++;
		$self->cb->($self) if $self->cb;
		$self->emit('cb');
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

sub end {
  my ($self) = @_;
  $self->{count_run}--;

  # Если исчерпан лимит
  if (  (!$self->{count_run})
	and $self->{limit}
	and $self->{count_total} >= $self->{limit})
  {
	$self->emit('finish');
	warn "finish event\n" if $DEBUG;
  }
  return;
}


sub DESTROY {
  my ($self) = @_;
  warn "Destroing $self\n" if $DEBUG;

  $self->drop();
  $self->SUPER::DESTROY() if SUPER->can('DESTROY');
  return;
}

# Сразу останавливает и все обнуляет
sub drop {
  my ($self) = @_;

  warn "Dropping $self ...\n" if $DEBUG;

  # Clear my timers
  if (my $loop = $self->ioloop) {
	warn "Dropping timers\n"              if $DEBUG;
	$loop->drop($self->{cb_timer_id})     if $self->{cb_timer_id};
	$loop->drop($self->{period_timer_id}) if $self->{period_timer_id};
  }

  #delete $self->{is_running};
  foreach (keys %$self) {
	delete $self->{$_};
  }

  return $self;
}

# Останавливает на время (не обнуляя limit_period)
# Запускаем таймер, который все таки limit_period обновит
sub stop {
  my ($self) = @_;

  warn "Stopping $self ...\n" if $DEBUG;

  # Clear my timers
  if (my $loop = $self->ioloop) {
	warn "Dropping cb timer\n" if $DEBUG;
	$loop->drop($self->{cb_timer_id}) if $self->{cb_timer_id};
	delete $self->{cb_timer_id};
	
	#Сохраняем обнуление периода и дропаемся, чтобы старт не запустило
	if($self->{period_timer_id}) {
	  $self->once(
		period => sub {
		  unless ($self->is_running) {
			warn "Drop period timer\n" if $DEBUG;
			$loop->drop($self->{period_timer_id});
			delete $self->{period_timer_id};
		  }
		  else {
			warn "$self is running again. Not drop period timer\n" if $DEBUG;
		  }
		  
	  }
	);
	}
	
  }
  delete $self->{is_running};
  return $self;
}

# Увеличивает общий лимит на 1 или $count раз, если $count указан в качестве второго аргумента
# запускает (если еще не запущен, пытается в общем) сделать $self->run
sub begin {
  my ($self, $count) = @_;
  $count||=1;
  $self->{limit}+=$count;
  $self->run;
  return;
}

sub wait {
  my $self = shift;

  $self->once(
	finish => sub {
	  my ($thr) = @_;
	  $thr->drop if $thr->{is_running};
	  $thr->ioloop->stop;
	}
  );
  $self->ioloop->start;
  return;

  #return wantarray ? @{$self->{args}} : $self->{args}->[0];
}


1;

=head1 NAME

MojoX::IOLoop::Throttle - throttle Mojo events 

=head1 VERSION

Version 0.01_11. (DEV)

=cut


=head1 SYNOPSIS

  use Mojo::Base -strict;
  use MojoX::IOLoop::Throttle;
  $| = 1;
  
  # New throttle object
  my $throttle = MojoX::IOLoop::Throttle->new(  
    limit_run =>    3,    # Allow not more than [limit_run] running (parallel,incomplete) jobs
  
    period =>       2,    # seconds
    limit_period => 4,    # do not start more than [limit_period] jobs per [period] seconds
  
    delay =>        0.05  # Simulate a little latency
  );
  
  my $count;
  
  # CallBack to throttle
  $throttle->cb(sub {
    my ($thr) = @_;
    my $rand_time = rand() / 5;
    say "Job $rand_time started";
    $thr->ioloop->timer(
      $rand_time => sub {
        say "job $rand_time ended";
        $count++;
        # Say that we end (to decrease limit_run count and let other job to start)
        $thr->end();
      }
    );
  });
  
  # Subscribe to finish event
  $throttle->on(finish => sub { say "I've processed $count jobs! Bye-bye"; });
  
  # Throttle 20 jobs!
  $throttle->begin(20);
  
  # Let's start
  $throttle->wait unless $throttle->ioloop->is_running;
  
  exit 0;



=head1 DESCRIPTION

  AHTUNG!!!

  This is a very first development release. Be patient. Documentation is in progress.
  You can find some working real-life examples in 'example' dir.
  
  If your are going to use this module now, use subclassing, because all method and options are experimental


=head1 FUNCTIONS


=head2 C<end>

in progress

=head2 C<wait>

in progress

=head2 C<drop>

in progress

=head2 C<begin>

in progress

=head2 C<run>

in progress

=head2 C<stop>

in progress

  

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
