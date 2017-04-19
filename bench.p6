use lib '.';
use NewIO;

my \N = 100;
my \FILE = 'sysio.dll';

do {
    my $path = IO::Path.new(FILE);
    my $i = 0;
    my $start = now;
    $i += $path.slurp(:bin).elems for ^N;
    my $end = now;
    say $end - $start;
    say $i;
}

do {
    my $path = NewIO::Path.new(FILE);
    my $i = 0;
    my $start = now;
    $i += $path.slurp(:bin).elems for ^N;
    my $end = now;
    say $end - $start;
    say $i;
}

do {
    my $path = NewIO::Path.new(FILE);
    my $i = 0;
    my $start = now;
    for ^N {
        my $fh := $path.open.raw;
        $i += $fh.readall.elems;
        $fh.close;
    }
    my $end = now;
    say $end - $start;
    say $i;
}
