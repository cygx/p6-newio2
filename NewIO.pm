use nqp;
use NativeCall;

my role NewIO { ... }

my class X::NewIO::Sys does X::IO {
    method message {
        "system error: $!os-error";
    }
}

my class X::NewIO::Unsupported does X::IO {
    has $.type;
    has $.operation;
    method message {
        "{$!type.^name} does not support operation '$!operation'";
    }
}

my class X::NewIO::BufferUnderflow does X::IO {
    method message {
        'buffer underflow'
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

    method stdhandle(uint32 $id) {
        my int64 $fd = sysio_stdhandle($id);
        die X::NewIO::Sys.new(os-error => self.error)
            if $fd == INVALID-FD;

        $fd;
    }

    proto method stdid(--> uint32) {*}
    multi method stdid(:$out! --> uint32) { 1 }
    multi method stdid(:$err! --> uint32) { 2 }
    multi method stdid(:$in? --> uint32)  { 0 }

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

my role NewIO::Handle {
    sub UNSUPPORTED($self, $routine) is hidden-from-backtrace {
        die X::NewIO::Unsupported.new(
            type => $self.WHAT,
            operation => $routine.name);
    }

    method close(--> True) {
        CATCH { when X::IO { .fail } }
        self.CLOSE;
    }

    method size(--> UInt:D) {
        UNSUPPORTED self, &?ROUTINE;
    }

    proto method seek($) {*}

    multi method seek(UInt:D $pos --> True) {
        UNSUPPORTED self, &?ROUTINE;
    }

    multi method seek(WhateverCode $pos --> True) {
        UNSUPPORTED self, &?ROUTINE;
    }

    method skip(Int:D $offset --> True) {
        UNSUPPORTED self, &?ROUTINE;
    }

    method tell(--> UInt:D) {
        UNSUPPORTED self, &?ROUTINE;
    }

    method read(UInt:D $n --> blob8:D) {
        CATCH { when X::IO { .fail } }
        my $buf := buf8.allocate($n);
        $buf.reallocate(self.READ($buf, 0, $n));
        $buf;
    }

    method readall(Bool :$close --> blob8:D) {
        UNSUPPORTED self, &?ROUTINE;
    }
}

my role NewIO::Seeking {
    method size(--> UInt:D) {
        CATCH { when X::IO { .fail } }
        self.GET-SIZE;
    }

    proto method seek($) {*}

    multi method seek(UInt:D $pos --> True) {
        CATCH { when X::IO { .fail } }
        self.SET-POS($pos);
    }

    multi method seek(WhateverCode $pos --> True) {
        CATCH { when X::IO { .fail } }
        self.SET-POS-FROM-END($pos(0));
    }

    method skip(Int:D $offset --> True) {
        CATCH { when X::IO { .fail } }
        self.SET-POS-FROM-CURRENT($offset);
    }

    method tell(--> UInt:D) {
        CATCH { when X::IO { .fail } }
        self.GET-POS;
    }

    method readall(Bool :$close --> blob8:D) {
        CATCH { when X::IO { .fail } }
        LEAVE self.CLOSE if $close;
        self.read(self.GET-SIZE - self.GET-POS);
    }
}

my role NewIO::Streaming {
    method readall(Bool :$close --> blob8:D) {
        CATCH { when X::IO { .fail } }
        die 'TODO';
    }

    method uniread(UInt:D $n, :$enc! --> Uni:D) {
        CATCH { when X::IO { .fail } }

        my $encoding := encoding $enc;
        my $range := $encoding.bytes-per-code;
        die X::Encoding::VariableLength.new(name => $encoding.^name)
            if $range > 1;

        my uint $unit = $range.max;
        my $buf := self.read($n * $unit);
        my uint $len = $buf.elems;
        die X::Encoding::PartialInput.new
            unless $len %% $unit;

        my uint $count = $len div $unit;
        my $uni := nqp::create(Uni);
        nqp::setelems($uni, $count);

        $encoding.decode($uni, $buf, my uint $, my uint $, $count);
        $uni;
    }
}

my role NewIO::Buffering {
    my constant BLOCKSIZE = 512;

    sub round-to-block(uint $n, uint $s = BLOCKSIZE) {
        (($n + $s - 1) div $s) * $s;
    }

    has $.encoding;
    has buf8 $!buffer = buf8.allocate(BLOCKSIZE);
    has uint $!have;
    has blob8 $!nl-out;
    has blob8 @!nl-in;

    submethod BUILD(:$enc = Encoding::Utf8) {
        $!encoding = encoding $enc;
        $!nl-out = $!encoding.LF;
        @!nl-in  = $!encoding.CRLF, $!encoding.LF;
    }

    method CLEAR-BUFFER {
        $!have = 0;
        $!buffer.reallocate(BLOCKSIZE)
    }

    method SHIFT-BUFFER(uint $n --> Nil) {
        when $n == $!have {
            self.CLEAR-BUFFER;
        }
        when $n < $!have {
            my uint $rest = $!have - $n;
            sysio.move($!buffer, $!buffer, 0, $n, $rest);
            $!buffer.reallocate(round-to-block $rest);
            $!have = $rest;
        }
        default {
            die X::NewIO::BufferUnderflow.new;
        }
    }

    method FILL-BUFFER(uint $n --> Nil) {
        if $n > $!have {
            my uint $size = $!buffer.elems;
            my uint $want = round-to-block $n;
            $!buffer.reallocate($want)
                if $want > $size;

            $!have = $!have + self.READ($!buffer, $!have, $want - $!have);
        }
    }

    method TAKE-BYTES-FROM-BUFFER(uint $n --> blob8:D) {
        my uint $count = $n min $!have;
        my uint $rest = $!have - $count;

        my $buf := buf8.allocate($count);
        sysio.copy($buf, $!buffer, 0, 0, $count);
        if $rest > 0 {
            sysio.move($!buffer, $!buffer, 0, $count, $rest);
            $!buffer.reallocate(round-to-block $rest);
        }

        $!have = $rest;
        $buf;
    }

    method TAKE-CODES-FROM-BUFFER(uint $n --> Uni:D) {
        my uint $count = $n min ($!have div $!encoding.bytes-per-code.min);

        my $uni := nqp::create(Uni);
        nqp::setelems($uni, $count);

        my uint $dstpos;
        my uint $srcpos;

        $!encoding.decode($uni, $!buffer, $dstpos, $srcpos, $count);
        nqp::setelems($uni, $dstpos);

        my uint $rest = $!have - $srcpos;
        if $rest > 0 {
            sysio.move($!buffer, $!buffer, 0, $srcpos, $rest);
            $!buffer.reallocate(round-to-block $rest);
        }
        
        $!have = $rest;
        $uni;
    }

    method read(UInt:D $n --> blob8:D) {
        CATCH { when X::IO { .fail } }
        self.FILL-BUFFER($n);
        self.TAKE-BYTES-FROM-BUFFER($n);
    }

    method uniread(UInt:D $n --> Uni:D) {
        CATCH { when X::IO { .fail } }
        self.FILL-BUFFER($n * $!encoding.bytes-per-code.max);
        self.TAKE-CODES-FROM-BUFFER($n);
    }
}

my class NewIO::BufferedSeeker does NewIO::Buffering does NewIO::Seeking {
    method skip(int $offset --> True) {
        CATCH { when X::IO { .fail } }

        when $offset == 0 {}
        when 0 < $offset <= $!have {
            self.SHIFT-BUFFER($offset);
        }
        default {
            self.SET-POS-FROM-CURRENT($offset - $!have);
            self.CLEAR-BUFFER;
        }
    }

    multi method seek(UInt:D $pos --> True) {
        CATCH { when X::IO { .fail } }
        self.SET-POS($pos);
        self.CLEAR-BUFFER;
    }

    multi method seek(WhateverCode $pos --> True) {
        CATCH { when X::IO { .fail } }
        self.SET-POS-FROM-END($pos(0));
        self.CLEAR-BUFFER;
    }

    method tell(--> UInt:D) {
        CATCH { when X::IO { .fail } }
        self.GET-POS - $!have;
    }
}

my class NewIO::BufferedStreamer does NewIO::Buffering does NewIO::Streaming {
    method skip(Int:D $offset --> True) {
        CATCH { when X::IO { .fail } }
        when $offset < 0 {
            die X::NewIO::Unsupported.new(
                type => ::?CLASS, operations => 'rewind');
        }
        when $offset == 0 {}
        when 0 < $offset <= $!have {
            self.SHIFT-BUFFER($offset);
        }
        default {
            self.SET-POS-FROM-CURRENT($offset - $!have);
            self.CLEAR-BUFFER;
        }
    }

    method uniread(UInt:D $n --> Uni:D) {
        CATCH { when X::IO { .fail } }
        self.FILL-BUFFER($n * $!encoding.bytes-per-code.max);
        self.TAKE-CODES-FROM-BUFFER($n);
    }
}

my class NewIO::OsHandle does NewIO::Handle {
    has int64 $.fd;

    method CLOSE(--> Nil) {
        sysio.close($!fd);
    }

    method READ(buf8:D $buf, uint $offset, uint $count --> uint) {
        sysio.read($!fd, $buf, $offset, $count);
    }

    method GET-SIZE(--> uint) {
        sysio.getsize($!fd);
    }

    method GET-POS(--> uint) {
        sysio.getpos($!fd);
    }
}

my class NewIO::FileHandle is NewIO::OsHandle is NewIO::BufferedSeeker {
    has Str $.path;
    has uint64 $.mode;

    method OPEN($src) {
        my $path := $src.absolute;
        my $mode := sysio.mode(|%_);
        self.new(:$path, :$mode, fd => sysio.open($path, $mode), |%_);
    }
}

my class NewIO::StdHandle is NewIO::OsHandle is NewIO::BufferedStreamer {
    has uint32 $.id;

    method OPEN($) {
        my $id := sysio.stdid(|%_);
        self.new(:$id, fd => sysio.stdhandle($id), |%_);
    }
}

my role NewIO[NewIO::Handle:U \Handle] {
    method open(--> NewIO::Handle:D) {
        CATCH { when X::IO { .fail } }
        Handle.OPEN(self, |%_);
    }

    method IO { self }

    proto method slurp {
        CATCH { when X::IO { .fail } }
        {*}
    }
    multi method slurp(:$bin! --> blob8:D) {
        Handle.OPEN(self, |%_).readall(:close);
    }
    multi method slurp(:$uni! --> Uni:D) {
        Handle.OPEN(self, |%_).unireadall(:close);
    }
    multi method slurp(--> Str:D) {
        Handle.OPEN(self, |%_).readallchars(:close);
    }
}

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
