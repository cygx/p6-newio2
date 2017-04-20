my constant sysio = Any;

my class X::NewIO::Unsupported does X::IO {
    has $.type;
    has $.operation;
    method message {
        "$!type does not support operation '$!operation'";
    }
}

my role NewIO { ... }

my role NewIO::Handle {
    sub UNSUPPORTED($routine) is hidden-from-backtrace {
        die X::NewIO::Unsupported.new(
            type => ::?CLASS,
            operation => $routine.name);
    }

    method close(--> True) {
        CATCH { when X::IO { .fail } }
        self.CLOSE;
    }

    method size(--> UInt:D) {
        UNSUPPORTED &?ROUTINE;
    }

    proto method seek($) {*}

    multi method seek(UInt:D $pos --> True) {
        UNSUPPORTED &?ROUTINE;
    }

    multi method seek(WhateverCode $pos --> True) {
        UNSUPPORTED &?ROUTINE;
    }

    method skip(Int:D $offset --> True) {
        UNSUPPORTED &?ROUTINE;
    }

    method tell(--> UInt:D) {
        UNSUPPORTED &?ROUTINE;
    }

    method read(UInt:D $n --> blob8:D) {
        CATCH { when X::IO { .fail } }
        my $buf := buf8.allocate($n);
        $buf.reallocate(self.READ($buf, 0, $n));
        $buf;
    }

    method readall(Bool :$close --> blob8:D) {
        UNSUPPORTED &?ROUTINE;
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

my role NewIO::Streaming {}

my role NewIO::Buffered {}

my role NewIO::BufferedSeeking does NewIO::Buffered does NewIO::Seeking {
    method skip(Int:D $offset --> True) {
        CATCH { when X::IO { .fail } }
        die 'TODO'
    }
}

my role NewIO::BufferedStreaming does NewIO::Buffered does NewIO::Streaming {
    method skip(Int:D $offset --> True) {
        CATCH { when X::IO { .fail } }
        die 'TODO'
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

my class NewIO::FileHandle is NewIO::OsHandle does NewIO::BufferedSeeking {
    has Str $.path;
    has uint64 $.mode;

    method OPEN($src) {
        my $path := $src.absolute;
        my $mode := sysio.mode(|%_);
        self.new(:$path, :$mode, fd => sysio.open($path, $mode), |%_);
    }
}

my class NewIO::StdHandle is NewIO::OsHandle does NewIO::BufferedStreaming {
    has uint32 $.id;

    method OPEN {
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
