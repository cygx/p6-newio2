use NativeCall;

my class X::NewIO::Sys does X::IO {
    method message {
        "system error: $!os-error";
    }
}

my class sysio {
    my constant NUL = "\0";
    my constant ENC = 'utf16';
    my constant INVALID-FD = -1;
    my constant ERROR_MAX = 512;

    sub sysio_error(buf8, uint64 --> uint64) is native<sysio> {*}
    sub sysio_open(Str is encoded(ENC), uint64 --> int64) is native<sysio> {*}
    sub sysio_stdhandle(uint32 --> int64) is native<sysio> {*}

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
}

my role NewIO { ... }

my role NewIO::Handle {
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
}

my class NewIO::BufferedOsHandle is NewIO::OsHandle does NewIO::BufferedHandle {
    has buf8 $!buffer;
    has uint $!pos;

    method AVAILABLE-BYTES {
        $!pos;
    }

    method CLEAR-BUFFER {
        $!pos = 0;
    }
}

my class NewIO::StreamingOsHandle is NewIO::BufferedOsHandle does NewIO::StreamingHandle {}

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
}

my class NewIO::Std does NewIO[NewIO::StdHandle] {}

my class NewIO::Path is IO::Path does NewIO[NewIO::FileHandle] {}

sub newio-open(IO() $_ = NewIO::Std, *%_) {
    .open(|%_);
}

my $patched = False;

sub EXPORT(Int $patch = 0) {
    if $patch {
        if !$patched {
            Str.^find_method('IO').wrap(method { NewIO::Path.new(self) });
            IO::Path.^find_method('open').wrap(NewIO::Path.^find_method('open'));
            &open.wrap(&newio-open);
            $patched = True;
        }

        BEGIN Map.new((IO => NewIO, '&open' => &newio-open));
    }
    else {
        BEGIN Map.new((NewIO => NewIO));
    }
}
