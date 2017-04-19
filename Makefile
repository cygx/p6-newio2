all: sysio.dll sysenc.dll .dummy

.dummy: NewIO.pm
	perl6 -I. -MNewIO -e 'use NewIO 1'
	touch .dummy

sysio.dll sysenc.dll: %.dll: %.c
	clang -fsyntax-only -Werror -Weverything $<
	gcc -shared -O3 -o $@ $<

clean:
	rm -rf .dummy sysio.dll
