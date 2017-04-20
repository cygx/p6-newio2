use nqp;
use NativeCall;

my role NewIO { ... }

my class X::NewIO::Sys does X::IO {
    method message {
        "system error: $!os-error";
    }
}

my class X::Encoding::VariableLength is Exception {
    has $.name;
    method message { "$!name is variable-length" }
}

my class X::Encoding::Unknown is Exception {
    has $.name;
    method message { "encoding '$!name' not known" }
}

my class X::Encoding::PartialInput is Exception {
    method message { "cannot decode input with partial code units" }
}

my class NewIO::Sys {
    my constant NUL = "\0";
    my constant ENC = 'utf16';
    my constant INVALID-FD = -1;
    my constant ERROR_MAX = 512;

    sub sysio_error(buf8, uint64 --> uint64) is native<sysio> {*}
    sub sysio_open(Str is encoded(ENC), uint64 --> int64) is native<sysio> {*}
    sub sysio_stdhandle(uint32 --> int64) is native<sysio> {*}
    sub sysio_read(int64, buf8, uint64, uint64 --> int64) is native<sysio> {*}
    sub sysio_copy(buf8, blob8, uint64, uint64, uint64) is native<sysio> {*}
    sub sysio_move(buf8, blob8, uint64, uint64, uint64) is native<sysio> {*}
    sub sysio_getsize(int64 --> int64) is native<sysio> {*}
    sub sysio_getpos(int64 --> int64) is native<sysio> {*}
    sub sysio_close(int64 --> int64) is native<sysio> {*}

    method mode(
        :$r, :$u, :$w, :$a, :$x, :$ru, :$rw, :$ra, :$rx,
        :$read is copy, :$write is copy, :$append is copy,
        :$create is copy, :$exclusive is copy, :$truncate is copy
    ) {
        $read = True if $r;
        $write = True if $u;
        $write = $create = $truncate = True if $w;
        $write = $create = $append = True if $a;
        $write = $create = $exclusive = True if $x;
        $read = $write = True if $ru;
        $read = $write = $create = $truncate = True if $rw;
        $read = $write = $create = $append = True if $ra;
        $read = $write = $create = $exclusive = True if $rx;
        ?$read +| ?$write +< 1 +| ?$append +< 2
            +| ?$create +< 3 +| ?$exclusive +< 4 +| ?$truncate +< 5;
    }

    method read(int64 $fd, buf8:D $buf, uint64 $offset, uint64 $count --> int64) {
        my int64 $read = sysio_read($fd, $buf, $offset, $count);
        die X::NewIO::Sys.new(os-error => self.error)
            if $read < 0;

        $read;
    }

    method error(--> Str:D) {
        my $buf := buf8.allocate(ERROR_MAX);
        $buf.reallocate(sysio_error($buf, $buf.elems));
        $buf.decode(ENC).chomp;
    }

    method open(Str:D $path, uint64 $mode --> int64) {
        my int64 $fd = sysio_open($path ~ NUL, $mode);
        die X::NewIO::Sys.new(os-error => self.error)
            if $fd == INVALID-FD;

        $fd;
    }

    proto method stdhandle {
        my int64 $fd = sysio_stdhandle({*});
        die X::NewIO::Sys.new(os-error => self.error)
            if $fd == INVALID-FD;

        $fd;
    }
    multi method stdhandle(:$out!) { 1 }
    multi method stdhandle(:$err!) { 2 }
    multi method stdhandle(:$in?)  { 0 }

    method copy(buf8:D $dst, blob8:D $src,
        uint64 $dstpos, uint64 $srcpos, uint64 $count --> Nil) {
        sysio_copy($dst, $src, $dstpos, $srcpos, $count);
    }

    method move(buf8:D $dst, blob8:D $src,
        uint64 $dstpos, uint64 $srcpos, uint64 $count --> Nil) {
        sysio_move($dst, $src, $dstpos, $srcpos, $count);
    }

    method getsize(int64 $fd --> int64) {
        my int64 $size = sysio_getsize($fd);
        die X::NewIO::Sys.new(os-error => self.error)
            if $size < 0;

        $size;
    }

    method getpos(int64 $fd --> int64) {
        my int64 $pos = sysio_getpos($fd);
        die X::NewIO::Sys.new(os-error => self.error)
            if $pos < 0;

        $pos;
    }

    method close(int64 $fd --> Nil) {
        my int64 $rv = sysio_close($fd);
        die X::NewIO::Sys.new(os-error => self.error)
            if $rv < 0;
    }
}

my constant sysio = NewIO::Sys;

my class U64Pair is repr<CStruct> {
    has uint64 $.a is rw;
    has uint64 $.b is rw;
}

my role Encoding {
    method LF(--> blob8:D) { ... }
    method CRLF(--> blob8:D) { ... }
    method bytes-per-code(--> Range:D) { ... }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) { ... }
}

my class Encoding::Latin1 does Encoding {
    sub sysenc_decode_latin1(Uni, blob8, U64Pair, uint64) is native<sysenc> {*}

    method LF(--> blob8:D) { BEGIN blob8.new(0x0A) }
    method CRLF(--> blob8:D) { BEGIN blob8.new(0x0D, 0x0A) }
    method bytes-per-code(--> Range:D) { BEGIN 1..1 }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) {
        my $pair := U64Pair.new(a => $dstpos, b => $srcpos);
        sysenc_decode_latin1($dst, $src, $pair, $count);
        $dstpos = $pair.a;
        $srcpos = $pair.b;
    }
}

my class Encoding::Utf8 does Encoding {
    method LF(--> blob8:D) { BEGIN blob8.new(0x0A) }
    method CRLF(--> blob8:D) { BEGIN blob8.new(0x0D, 0x0A) }
    method bytes-per-code(--> Range:D) { BEGIN 1..4 }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) {
        !!!
    }
}

my class Encoding::Utf16le does Encoding {
    method LF(--> blob8:D) { !!! }
    method CRLF(--> blob8:D) { !!! }
    method bytes-per-code(--> Range:D) { BEGIN 2..4 }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) {
        !!!
    }
}

my class Encoding::Utf16be does Encoding {
    method LF(--> blob8:D) { !!! }
    method CRLF(--> blob8:D) { !!! }
    method bytes-per-code(--> Range:D) { BEGIN 2..4 }
    method decode(Uni:D $dst, blob8:D $src, uint64 $dstpos is rw,
        uint64 $srcpos is rw, uint64 $count --> Nil) {
        !!!
    }
}

my class Encoding::Utf32le does Encoding {
    method LF(--> blob8:D) { !!! }
    method CRLF(--> blob8:D) { !!! }
    method bytes-per-code(--> Range:D) { BEGIN 4..4 }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) {
        !!!
    }
}

my class Encoding::Utf32be does Encoding {
    method LF(--> blob8:D) { !!! }
    method CRLF(--> blob8:D) { !!! }
    method bytes-per-code(--> Range:D) { BEGIN 4..4 }
    method decode(Uni:D $dst, blob8:D $src, uint64 $dstpos is rw,
        uint64 $srcpos is rw, uint64 $count --> Nil) {
        !!!
    }
}

my %ENCODINGS =
    'latin1'    => Encoding::Latin1,
    'utf8'      => Encoding::Utf8,
    'utf16'     => Encoding::Utf16le,
    'utf16-le'  => Encoding::Utf16le,
    'utf16-be'  => Encoding::Utf16be,
    'utf32'     => Encoding::Utf32le,
    'utf32-le'  => Encoding::Utf32le,
    'utf32-be'  => Encoding::Utf32be;

sub encoding($_) {
    when Encoding { $_ }
    when %ENCODINGS{$_}:exists { %ENCODINGS{$_} }
    default { fail X::Encoding::Unknown(name => ~$_) }
}

# PASTE HERE

my class NewIO::Std does NewIO[NewIO::StdHandle] {}

my class NewIO::Path is IO::Path does NewIO[NewIO::FileHandle] {
    multi method slurp(:$bin! --> blob8:D) {
        my int64 $fd = sysio.open(self.absolute, 0);
        do {
            LEAVE sysio.close($fd);
            my int64 $size = sysio.getsize($fd);
            my $buf := buf8.allocate($size);
            $buf.reallocate(sysio.read($fd, $buf, 0, $size));
            $buf;
        }
    }
}

proto sub open2($?, *%) {*}
multi sub open2(Cool $_, *%_) { NewIO::Path.new($_).open(|%_) }
multi sub open2(IO() $_ = NewIO::Std, *%_) { .open(|%_)}

my $patched = False;

sub EXPORT(Int $patch = 0) {
    if $patch {
        if !$patched {
            Str.^find_method('IO').wrap(method { NewIO::Path.new(self) });
            IO::Path.^find_method('open').wrap(NewIO::Path.^find_method('open'));
            &open.wrap(&open2);
            $patched = True;
        }

        BEGIN Map.new((IO => NewIO, '&open' => &open2));
    }
    else {
        BEGIN Map.new((NewIO => NewIO, '&open2' => &open2));
    }
}
