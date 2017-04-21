NOWARN := padded

p6io2.dll: %.dll: %.c
	clang -fsyntax-only -Werror -Weverything $(NOWARN:%=-Wno-%) $<
	gcc -shared -O3 -o $@ $<
