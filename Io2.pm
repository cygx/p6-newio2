use NativeCall;
use nqp;

my constant intptr = ssize_t;
my class Io2 is repr<Uninstantiable> { ... }

my class X::Io2::Sys is Exception {
    has $.kind = 'io';
    has $.oserror = Io2.oserror;
    method message { "$!kind error: $!oserror" }
}

my class Io2 {
    my constant SYSENC = 'utf16';
    my constant ERROR_MAX = 512;
    my constant NUL = "\0";
    my constant INVALID_FD = -1;

    sub oserror(buf8, uint32 --> uint32)
        is native<p6io2> is symbol<p6io2_oserror> {*}

    sub open(Str is encoded(SYSENC), uint32 --> intptr)
        is native<p6io2> is symbol<p6io2_open> {*}

    sub close(intptr --> int32)
        is native<p6io2> is symbol<p6io2_close> {*}

    sub stdhandle(uint32 $id --> intptr)
        is native<p6io2> is symbol<p6io2_stdhandle> {*}

    sub getsize(intptr --> int64)
        is native<p6io2> is symbol<p6io2_getsize> {*}

    sub getpos(intptr --> int64)
        is native<p6io2> is symbol<p6io2_getpos> {*}

    method oserror(--> Str:D) {
        my $buf := buf8.allocate(ERROR_MAX);
        $buf.reallocate(oserror($buf, $buf.elems));
        $buf.decode(SYSENC).chomp;
    }

    method open(Str:D $path, uint32 $mode --> intptr) {
        my intptr $fd = open($path ~ NUL, $mode);
        die X::Io2::Sys.new if $fd == INVALID_FD;
        $fd;
    }

    method close(intptr $fd --> Nil) {
        close($fd) == 0 or die X::Io2::Sys.new;
    }

    method getsize(intptr $fd --> uint64) {
        my int64 $size = getsize($fd);
        die X::Io2::Sys.new if $size == -1;
        $size;
    }

    method getpos(intptr $fd --> uint64) {
        my int64 $pos = getpos($fd);
        die X::Io2::Sys.new if $pos == -1;
        $pos;
    }

    method stdin  { stdhandle(0) }
    method stdout { stdhandle(1) }
    method stderr { stdhandle(2) }

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
}

my class Io2::Buffer is repr<CStruct> {
    has intptr $.bytes;
    has uint32 $.size;
    has uint32 $.pos;

    method bytes { nativecast(CArray[uint8], $.bytes(:ptr)) }

    method resize(uint32 $size)
        is native<p6io2> is symbol<p6io2_buffer_resize> {*}

    method discard()
        is native<p6io2> is symbol<p6io2_buffer_discard> {*}

    method fill(intptr $fd, bool $retry --> int32)
        is native<p6io2> is symbol<p6io2_buffer_fill> {*}

    method shift(uint32 $count)
        is native<p6io2> is symbol<p6io2_buffer_shift> {*}

    method clear(--> Nil) {
        $!pos = 0;
    }

    submethod wrap(buf8:D $buf) {
        self.new(
            size => $buf.elems,
            bytes => nativecast(Pointer, $buf)
        );
    }
}

my class Io2::DynBuffer is repr<CStruct> is Io2::Buffer {
    my constant BLOCKSIZE = 512;
    my constant LIMIT = 64 * 1024;

    has uint32 $.blocksize = BLOCKSIZE;
    has uint32 $.limit = LIMIT;

    submethod TWEAK { self.resize($!blocksize) }

    method drain(Io2::Buffer $buf)
        is native<p6io2> is symbol<p6io2_dynbuffer_drain> {*}

    method refill(intptr $fd, uint32 $n, bool $retry --> int32)
        is native<p6io2> is symbol<p6io2_dynbuffer_refill> {*}
}

my class Io2::Handle {
    has intptr $.fd;
    has Io2::DynBuffer $.buffer = Io2::DynBuffer.new;

    method close {
        $!buffer.discard;
        Io2.close($!fd);
    }

    method read(uint32 $n, Bool :$retry = False --> buf8:D) {
        my $buf := buf8.allocate($n);
        return $buf if $n == 0;

        my $stooge := Io2::Buffer.wrap($buf);
        $!buffer.drain($stooge);
        $stooge.fill($!fd, $retry) >= 0
            or die X::Io2::Sys.new;

        $buf.reallocate($stooge.pos);
        $buf || Nil;
    }
}

my class Io2::FileHandle is Io2::Handle {
    has Str $.path;
    has uint32 $.mode;

    method size(--> uint64) {
        Io2.getsize($.fd);
    }

    method tell(--> uint64) {
        Io2.getpos($.fd) - $.buffer.pos;
    }

    method readall(Bool :$close = False --> buf8:D) {
        LEAVE self.close if $close;
        self.read(self.size - self.tell);
    }

    proto method seek($) {*}

    multi method seek(uint64 $pos --> True) {
        Io2.setpos($.fd, $pos, 0);
        $.buffer.clear;
    }

    multi method seek(WhateverCode $pos --> True) {
        Io2.setpos($.fd, $pos(0), 2);
        $.buffer.clear;
    }

    method skip(int64 $offset --> True) {
        when $offset == 0 {}
        when 0 < $offset <= $.buffer.pos {
            $.buffer.shift($offset);
        }
        default {
            Io2.setpos($.fd, $offset - $.buffer.pos, 1);
            $.buffer.clear;
        }
    }
}

my class Io2::StreamHandle is Io2::Handle {}

say Io2::FileHandle.new(fd => Io2.open('.gitignore', 0)).readall.decode.perl;
