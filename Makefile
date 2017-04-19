all: .dummy sysio.dll

.dummy: NewIO.pm
	perl6 -I. -MNewIO -e 'use NewIO 1'
	touch .dummy

sysio.dll: %.dll: %.c
	clang -fsyntax-only -Werror -Weverything $<
	gcc -shared -O3 -o $@ $<

clean:
	rm -rf .dummy sysio.dll
