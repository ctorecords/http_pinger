package pinger;
use AnyEvent 5;
use AnyEvent::HTTP;
use Time::HiRes;
use uni::perl ':dumper';

sub after ($&) {
    my $after = shift;
    my $cb    = shift;
    my $t; $t =  AnyEvent->timer(
        after => $after,
        cb    => sub { undef $t; goto &$cb }
    );
    return;
}

sub new {
    my $pkg = shift;
    my $self = bless { timeout=>15, pool=> 2, @_ }, $pkg;

    $self->{f} = Pool->new( 1..$self->{pool} );

    $self;
}

sub _check {
    my $self  = shift;
    my $cb    = pop;
    my @urls  = @_;
    my $count = scalar @urls;
    my %result;

    my $checker; $checker = sub {
        if ( my $url = shift @urls ) {
            $self->{f}->take( sub {
                my $fetcher = shift;
                http_request HEAD => $url => ( timeout=> $self->{timeout} ) =>
                    sub {
                        my ($body, $hdr) = @_;
                        $self->{f}->return($fetcher);
                        $result{$url} = ( defined $body and $hdr->{Status} =~ /^2/ ) ? 1 : 0;
                    }
                ;
                $checker->();
            } );
        }
        elsif( scalar keys %result == $count ) {
            $cb->(\%result);
        }
        else {
            after 0.01 => sub { $checker->() }
        }
    };
    $checker->();
}

sub check {
    my $self = shift;

    my %result;
    my $cv = AE::cv;
    $self->_check( @_ => sub {
        if ( my $ok = shift ) {
            %result = %$ok;
        }
        elsif( my $error = shift) {
            warn "Error: $error", $/;
        }
        $cv->send;
    } );

    $cv->recv;
    return %result;
}

1;

package Pool;
use List::Util 'shuffle';

sub new {
    my $pkg = shift;
    my $self = bless { items => { waiting => [], product=> [] }, }, $pkg;

    $self->add($_) for (@_);

    $self;
}

sub add {
    my $self = shift;

    $self->{count}++;
    push @{$self->{items}{product}}, shift();

    $self;
}

sub take {
    my $self = shift;
    my $cb = shift or die "cb required for take_item at @{[(caller)[1,2]]}\n";
    if (@{$self->{items}{product}}) {
        @{$self->{items}{product}} = shuffle @{$self->{items}{product}};
        $cb->(shift @{$self->{items}{product}});
    } else {
        push @{$self->{items}{waiting}},$cb
    }
}

sub return:method {
    my $self = shift;
    push @{ $self->{items}{product} }, @_;
    $self->take(shift @{ $self->{items}{waiting} }) if @{ $self->{items}{waiting} };
}

1;

