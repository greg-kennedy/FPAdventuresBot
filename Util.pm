package Util;

# Short form of Twitter::API::Util because FreeBSD does not package one for me

use 5.14.1;
use warnings;
use Carp qw/croak/;
use Time::Local qw/timegm/;

my %month;
@month{qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/} = 0..11;
sub _parse_ts {
    local $_ = shift() // return;

    # "Wed Jun 06 20:07:10 +0000 2012"
    my ( $M, $d, $h, $m, $s, $y ) = /
        ^(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat)
        \ (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)
        \ (\d\d)\ (\d\d):(\d\d):(\d\d)
        \ \+0000\ (\d{4})$
    /x or return;
    return ( $s, $m, $h, $d, $month{$M}, $y - 1900 );
};

sub timestamp_to_gmtime    { gmtime timestamp_to_time($_[0]) }
sub timestamp_to_localtime { localtime timestamp_to_time($_[0]) }
sub timestamp_to_time      {
    my $ts = shift // return undef;
    my @t = _parse_ts($ts) or croak "invalid timestamp: $ts";
    timegm @t;
}

1;

