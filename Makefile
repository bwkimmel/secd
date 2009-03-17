# define targets here
TARGETS=compiler.lob

CLEANFILES=$(TARGETS) secd *.o

CC=gcc
AS=nasm
ARCH=macho
ASFLAGS=-f $(ARCH)
DEBUG=0

all: $(TARGETS)

secd: support.o string.o secd.o main.o
	ld -o secd $^
	if (($(DEBUG) == 0)); then strip $@; fi

clean:
	-rm -f $(CLEANFILES)

redo: clean all

%.o : %.c
	$(CC) -c $< -o $@

%.o : %.asm
	$(AS) $(ASFLAGS) -o $@ $<

%.lob : %.lso compiler.lob secd
	cat compiler.lob $< | ./secd > $@
