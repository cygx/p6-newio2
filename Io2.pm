use NativeCall;
use nqp;

my class Io2 is repr<Uninstantiable> { ... }

my class X::Io2::Sys is Exception {
    has $.kind = 'io';
    has $.oserror = Io2.oserror;
    method message { "$!kind error: $!oserror" }
}

my class Io2::Buffer is repr<CStruct> {
    my constant intptr = ssize_t;

    has intptr $.bytes;
    has uint32 $.size;
    has uint32 $.pos;

    method RESIZE($size) {
        $!bytes = Io2.realloc($.bytes(:ptr), $size);
        $!size = $size;
    }

    method DISCARD {
        Io2.free($.bytes(:ptr));
        $!size = 0;
    }

    submethod wrap(buf8:D $buf) {
        self.new(
            size => $buf.elems,
            bytes => nativecast(Pointer, $buf)
        );
    }

    multi method bytes { nativecast(CArray[uint8], $.bytes(:ptr)) }
    multi method bytes(:$ptr!) { nqp::box_i($!bytes, Pointer) }
}

my class Io2::DynBuffer is repr<CStruct> is Io2::Buffer {
    my constant BLOCKSIZE = 512;
    my constant LIMIT = 64 * 1024;

    has uint32 $.blocksize = BLOCKSIZE;
    has uint32 $.limit = LIMIT;

    submethod TWEAK { self.RESIZE($!blocksize) }
}

my class Io2::Encoding is repr<CPointer> {
    method utf8 { INIT Io2::Encoding }
    method latin1 { INIT Io2::Encoding }
}

my class Io2 {
    my constant SYSENC = 'utf16';
    my constant LIBC = 'msvcrt';
    my constant ERROR_MAX = 512;
    my constant NUL = "\0";
    my constant INVALID_FD = -1;
    my constant INVALID_READ = 0xFF_FF_FF_FF;

    sub malloc(size_t --> Pointer) is native(LIBC) {*}
    sub realloc(Pointer, size_t --> Pointer) is native(LIBC) {*}
    sub free(Pointer) is native(LIBC) {*}

    sub oserror(buf8, uint32 --> uint32)
        is native<p6io2> is symbol<p6io2_oserror> {*}

    sub sysopen(Str is encoded(SYSENC), uint32 --> int64)
        is native<p6io2> is symbol<p6io2_sysopen> {*}

    sub close(int64 --> int32)
        is native<p6io2> is symbol<p6io2_close> {*}

    sub stdhandle(uint32 $id --> int64)
        is native<p6io2> is symbol<p6io2_stdhandle> {*}

    sub read(int64 $fd, Io2::Buffer:D $buf, uint32 $n --> uint32)
        is native<p6io2> is symbol<p6io2_read> {*}

    method malloc($size) { malloc($size) }
    method realloc($ptr, $size) { realloc($ptr, $size) }
    method free($ptr) { free($ptr) }

    method oserror(--> Str:D) {
        my $buf := buf8.allocate(ERROR_MAX);
        $buf.reallocate(oserror($buf, $buf.elems));
        $buf.decode(SYSENC).chomp;
    }

    method sysopen(Str:D $path, uint32 $mode --> int64) {
        my int64 $fd = sysopen($path ~ NUL, $mode);
        die X::Io2::Sys.new if $fd == INVALID_FD;
        $fd;
    }

    method close(int64 $fd --> Nil) {
        die X::Io2::Sys.new
            if close($fd) < 0;
    }

    method read(int64 $fd, Io2::Buffer:D $buf, uint32 $n --> uint32) {
        my uint32 $rv = read($fd, $buf, $n);
        die X::Io2::Sys.new if $rv == INVALID_READ;
        $rv;
    }

    method stdin  { stdhandle(0) }
    method stdout { stdhandle(1) }
    method stderr { stdhandle(2) }
}

my class Io2::OsHandle {
    has int64 $.fd;

    method CLOSE { Io2.close($!fd) }

    method READ(Io2::Buffer:D $buf, uint32 $n --> uint32) {
        Io2.read($!fd, $buf, $n);
    }

    method close { self.CLOSE }

    method read(uint32 $n --> buf8:D) {
        my $buf := buf8.allocate($n);
        $buf.reallocate(self.READ(Io2::Buffer.wrap($buf), $n) || return Nil);
        $buf;
    }
}

my class Io2::BufferedOsHandle is Io2::OsHandle {
    has Io2::DynBuffer $.buffer = Io2::DynBuffer.new;
    has Io2::Encoding $.encoding = Io2::Encoding.utf8;

    method close {
        $!buffer.DISCARD;
        self.CLOSE;
    }
}

say Io2::OsHandle.new(fd => Io2.stdin).read(100).decode.perl;
