use nqp;
use NativeCall;

my role NewIO { ... }

my class X::NewIO::Sys does X::IO {
    method message {
        "system error: $!os-error";
    }
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
    method min-bytes-per-code(--> UInt:D) { ... }
    method max-bytes-per-code(--> UInt:D) { ... }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) { ... }
}

my class Encoding::Latin1 does Encoding {
    sub sysenc_decode_latin1(Uni, blob8, U64Pair, uint64) is native<sysenc> {*}

    method min-bytes-per-code(--> UInt:D) { 1 }
    method max-bytes-per-code(--> UInt:D) { 1 }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) {
        my $pair := U64Pair.new(a => $dstpos, b => $srcpos);
        sysenc_decode_latin1($dst, $src, $pair, $count);
        $dstpos = $pair.a;
        $srcpos = $pair.b;
    }
}

my class Encoding::Utf8 does Encoding {
    method min-bytes-per-code(--> UInt:D) { 1 }
    method max-bytes-per-code(--> UInt:D) { 4 }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) {
        !!!
    }
}

my class Encoding::Utf16le does Encoding {
    method min-bytes-per-code(--> UInt:D) { 2 }
    method max-bytes-per-code(--> UInt:D) { 4 }
    method decode(Uni:D $dst, blob8:D $src, uint $dstpos is rw,
        uint $srcpos is rw, uint $count --> Nil) {
        !!!
    }
}

my class Encoding::Utf16be does Encoding {
    method min-bytes-per-code(--> UInt:D) { 2 }
    method max-bytes-per-code(--> UInt:D) { 4 }
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
    'utf16-be'  => Encoding::Utf16be;

my role NewIO::Handle {
    method raw(--> NewIO::Handle:D) {
        self.RAW;
    }

    method close(--> True) {
        self.CLOSE;
    }

    method size(--> UInt:D) {
        self.GET-SIZE;
    }

    proto method seek($) {*}

    multi method seek(UInt:D $pos --> True) {
        self.SET-POS($pos);
    }

    multi method seek(WhateverCode $pos --> True) {
        self.SET-POS-FROM-END($pos(0));
    }

    method skip(Int:D $offset --> True) {
        self.SET-POS-FROM-CURRENT($offset);
    }

    method tell(--> UInt:D) {
        self.GET-POS;
    }

    method read(UInt:D $n --> blob8:D) {
        my $buf := buf8.allocate($n);
        $buf.reallocate(self.READ($buf, 0, $n));
        $buf;
    }

    method readall(--> blob8:D) {
        self.read(self.GET-SIZE - self.GET-POS);
    }
}

my role NewIO::BufferedHandle {
    multi method seek(UInt:D $pos --> True) {
        self.SET-POS($pos);
        self.CLEAR-BUFFER;
    }

    multi method seek(WhateverCode $pos --> True) {
        self.SET-POS-FROM-END($pos(0));
        self.CLEAR-BUFFER;
    }

    method skip(Int:D $offset is copy --> True) {
        when $offset == 0 {}
        when 0 < $offset <= self.AVAILABLE-BYTES {
            self.SHIFT-BUFFER($offset);
        }
        default {
            self.SET-POS-FROM-CURRENT($offset - self.AVAILABLE-BYTES);
            self.CLEAR-BUFFER;
        }
    }

    method tell(--> UInt:D) {
        self.GET-POS - self.AVAILABLE-BYTES;
    }

    method read(UInt:D $n --> blob8:D) {
        self.FILL-BUFFER($n);
        self.TAKE-AVAILABLE-BYTES($n);
    }

    method uniread(UInt:D $n --> Uni:D) {
        self.FILL-BUFFER($n * self.ENCODING.max-bytes-per-code);
        self.TAKE-AVAILABLE-CODES($n);
    }
}

my role NewIO::StreamingHandle {
    multi method seek(UInt:D $pos --> True) {
        self.NOT-SUPPORTED;
    }

    multi method seek(WhateverCode $pos --> True) {
        self.NOT-SUPPORTED;
    }

    method skip(Int:D $offset --> True) {
        when $offset < 0 {
            self.NOT-SUPPORTED('cannot rewind a stream');
        }
        when $offset == 0 {}
        when 0 < $offset <= self.AVAILABLE-BYTES {
            self.SHIFT-BUFFER($offset);
        }
        default {
            self.SET-POS-FROM-CURRENT($offset - self.AVAILABLE-BYTES);
            self.CLEAR-BUFFER;
        }
    }

    method tell(--> UInt:D) {
        self.NOT-SUPPORTED;
    }
}

my class NewIO::OsHandle does NewIO::Handle {
    has int64 $.fd;

    method SET($!fd) {}

    method RAW { self }

    method CLOSE {
        sysio.close($!fd);
    }

    method READ(buf8:D $buf, UInt:D $offset, UInt:D $count --> UInt:D) {
        sysio.read($!fd, $buf, $offset, $count);
    }

    method GET-SIZE {
        sysio.getsize($!fd);
    }

    method GET-POS {
        sysio.getpos($!fd);
    }
}

my class NewIO::BufferedOsHandle is NewIO::OsHandle does NewIO::BufferedHandle {
    my constant BLOCKSIZE = 512;

    sub round-to-block(uint $n, uint $s = BLOCKSIZE) {
        (($n + $s - 1) div $s) * $s;
    }

    has buf8 $!buffer = buf8.allocate(BLOCKSIZE);
    has uint $!pos;
    has $.encoding;

    submethod BUILD(:$enc = Encoding::Utf8) {
        $!encoding = do given $enc {
            when Encoding { $enc }
            when %ENCODINGS{$enc}:exists { %ENCODINGS{$enc} }
            default { die "unsupported encoding '$enc'" }
        }
    }

    method RAW {
        NewIO::OsHandle.new(:$.fd);
    }

    method ENCODING {
        $!encoding;
    }

    method AVAILABLE-BYTES {
        $!pos;
    }

    method CLEAR-BUFFER {
        $!pos = 0;
    }

    method FILL-BUFFER(UInt:D $n --> Nil) {
        if $n > $!pos {
            my uint $size = $!buffer.elems;
            my uint $want = round-to-block $n;
            $!buffer.reallocate($want)
                if $want > $size;

            $!pos = $!pos + self.READ($!buffer, $!pos, $want - $!pos);
        }
    }

    method TAKE-AVAILABLE-BYTES(UInt:D $n --> blob8:D) {
        my uint $count = $n min $!pos;
        my uint $rest = $!pos - $count;

        my $buf := buf8.allocate($count);
        sysio.copy($buf, $!buffer, 0, 0, $count);
        sysio.move($!buffer, $!buffer, 0, $count, $rest)
            if $rest > 0;

        $!pos = $rest;
        $buf;
    }

    method TAKE-AVAILABLE-CODES(UInt:D $n --> Uni:D) {
        my $enc := self.ENCODING;
        my uint $count = $n min ($!pos div $enc.min-bytes-per-code);

        my $uni := nqp::create(Uni);
        nqp::setelems($uni, $count);

        my uint $dstpos;
        my uint $srcpos;

        $enc.decode($uni, $!buffer, $dstpos, $srcpos, $count);
        nqp::setelems($uni, $dstpos);

        my uint $rest = $!pos - $srcpos;
        sysio.move($!buffer, $!buffer, 0, $srcpos, $rest) if $rest > 0;
        $!pos = $rest;

        $uni;
    }
}

my class NewIO::StreamingOsHandle is NewIO::BufferedOsHandle
    does NewIO::StreamingHandle {}

my class NewIO::FileHandle is NewIO::BufferedOsHandle {
    has Str $.path;
    has uint64 $.mode;

    submethod BUILD(:$io) {
        $!path = $io.absolute;
        $!mode = sysio.mode(|%_);
        self.SET(sysio.open($!path, $!mode));
    }
}

my class NewIO::StdHandle is NewIO::StreamingOsHandle {
    submethod BUILD {
        self.SET(sysio.stdhandle(|%_));
    }
}

my role NewIO[NewIO::Handle:U \HANDLE] {
    method open(--> NewIO::Handle:D) {
        HANDLE.new(io => self, |%_);
    }

    method IO { self }

    proto method slurp {*}
    multi method slurp(:$bin! --> blob8:D) {
        my \handle = self.open(|%_);
        LEAVE handle.close;
        handle.readall;
    }
    multi method slurp(:$uni! --> Uni:D) {
        my \handle = self.open(|%_);
        LEAVE handle.close;
        handle.unireadall;
    }
    multi method slurp(--> Str:D) {
        my \handle = self.open(|%_);
        LEAVE handle.close;
        handle.readallchars;
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
