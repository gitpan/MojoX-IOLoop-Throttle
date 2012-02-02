package MojoX::IOLoop::Throttle;
use Mojo::Base 'Mojo::EventEmitter';

our $VERSION = '0.01_03';
$VERSION = eval $VERSION;

use Mojo::IOLoop;
use Carp 'croak';

my $DEBUG = $ENV{MOJO_THROTTLE_DEBUG};

has ioloop => sub { Mojo::IOLoop->singleton };

# drop timers on undef $throttle
has autodrop => 1;


sub throttle {
  my ($self, %args) = @_;

  my $limit_period = $args{limit_period} || 0;
  my $limit_run    = $args{limit_run}    || 0;
  my $limit_total  = $args{limit}        || 0;
  
  # Это необходимо для end, запускать финиш или нет
  $self->{limit_total} = $limit_total;

  my $delay  = exists $args{delay} ? $args{delay} : '0.0001';
  my $period = $args{period};


  # subscribe call back
  $self->on(cb => $args{cb}) if $args{cb};

  # Check if we are already running
  croak 'This throttle is already running' if $self->{is_running}++;
  warn "Starting new $self\n" if $DEBUG;

  # defaults
  my $ioloop       = $self->ioloop;
  my $period_count = 0;
  $self->{running_count} = 0;
  $self->{count_total}   = 0;

  if ($period) {
    $self->{period_timer_id} =
      $ioloop->recurring(
      $period => sub { $period_count = 0; $self->emit_safe('period'); });
  }

  $self->{cb_timer_id} = $ioloop->recurring(
    $delay => sub {
      
      # Если никто не подписан, нам делать нечего
      unless ($self->has_subscribers('cb')) {
        warn "No subscribers. Maybe error? $self\n" if $DEBUG;
        $self->drop;
        return;
      }
      
      unless (!$limit_total || $self->{count_total} < $limit_total) {
        warn "The limit $limit_total is exhausted\n" if $DEBUG;
        $self->drop;
        return;
      }

      # Проверяем душить или нет. Нужно чтобы был задан хотя бы один из параметров limit or limit_run, без этого будет drain
      my $cond = (
        # Не вышли за пределы лимита или лимит не задан, но задан хотя бы limit_run
        ($period_count < $limit_period || (!$limit_period))

        # Не вышли за пределы работающих параллельно задач или если такого лимита нет, то задан хотя бы limit
          && (($self->{running_count} < $limit_run)
          || (!$limit_run))
      );

      if ($cond) {
        $period_count++;
        $self->{running_count}++;
        $self->{count_total}++;
        $self->emit('cb');
        return;
        
      }
      # Если вышли за пределы лимита в периоде и нет запущенных коллбэков
      elsif (!$self->{running_count}) {
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
  $self->{running_count}--;
  
  # Если исчерпан лимит
  if ( (!$self->{running_count}) and $self->{limit_total} and $self->{count_total} >= $self->{limit_total}) {  
    $self->emit_safe('finish');
    warn "finish event\n" if $DEBUG;
  }
  return;
}


sub DESTROY {
  my ($self) = @_;
  warn "Destroing $self\n" if $DEBUG;
  
  $self->drop() if $self->autodrop;
  $self->SUPER::DESTROY() if SUPER->can('DESTROY');
  return;
}

sub drop {
  my ($self) = @_;

  warn "Dropping $self ...\n" if $DEBUG;

  delete $self->{is_running};

  # Clear my timers
  if (my $loop = $self->ioloop) {
    warn "Dropping timers\n"              if $DEBUG;
    $loop->drop($self->{cb_timer_id})     if $self->{cb_timer_id};
    $loop->drop($self->{period_timer_id}) if $self->{period_timer_id};
  }
  delete $self->{is_running};
  return $self;
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

Version 0.01_03. (DEV)

=cut


=head1 SYNOPSIS
    
    use  MojoX::IOLoop::Throttle;
    $|=1;
    
    # New throttle object
    my $throttle = MojoX::IOLoop::Throttle->new();    
    
    # Subscribe to finish event
    $throttle->on(finish => sub { say "All done! Bye-bye"; });
    
    # Throttle!
    $throttle->throttle(
      limit => 20,     # Play [total number] jobs(callbacks)
      limit_run => 3,               # But allow not more than 3 running (parallel,incomplete) jobs
    
      period       => 2,            # 10 seconds
      limit_period => 4,            # do not start more then 5 jobs per 10 seconds "period"
    
      delay => 0.05,                # simulate (or not) a little latency between shots (timer resolution)
      cb => sub {
        my ($thr) = @_;
        my $rand_time = rand() / 5;
        say "Job $rand_time started";
        $thr->ioloop->timer($rand_time => sub {          
          say "job $rand_time ended";
          
          # Say that we end (to decrease limit_run count and let other job to start)
          $thr->end();
          });
      }
    );
    
    # Let's start
    $throttle->wait unless $throttle->ioloop->is_running;
    
    exit 0;;


=head1 DESCRIPTION

  AHTUNG!!!

  This is a very first development release. Be patient. Documentation is in progress.
  You can find some working real-life examples in 'example' dir.
  
  If your are going to use this module now, use subclassing, because all method and options are experimental


=head1 FUNCTIONS

=head2 C<wait>

in progress

=head2 C<end>

in progress

=head2 C<wait>

in progress

=head2 C<throttle>

in progress

=head2 C<drop>

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
