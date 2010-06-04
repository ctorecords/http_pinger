use Data::Dumper;
use pinger;

die "Usage: $/perl $0 http://somedomain1.com/ http://somedomain2.com/ ...", $/ unless @ARGV;
print Dumper ({
    pinger->new( timeout=> 3, pool=>10 )->check(@ARGV)
});
