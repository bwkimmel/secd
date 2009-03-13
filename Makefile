# define targets here
TARGETS=secd

CLEANFILES=$(TARGETS) *.o

CC=gcc
AS=nasm
ARCH=macho
ASFLAGS=-f $(ARCH)

all: $(TARGETS)

secd: support.o string.o secd.o test.o
	ld -o secd $^

clean:
	-rm -f $(CLEANFILES)

redo: clean all

%.o : %.c
	$(CC) -c $< -o $@

%.o : %.asm
	$(AS) $(ASFLAGS) -o $@ $<

