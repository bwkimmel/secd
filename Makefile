# define targets here
TARGETS=secd

CLEANFILES=$(TARGETS) *.o

M4=m4
CC=gcc
AS=nasm -g
ARCH=elf32
ASFLAGS=-f $(ARCH)
LD=ld
LDFLAGS=-m elf_i386
DEBUG=0

all: $(TARGETS)

secd: support.o string.o heap.o secd.o main.o
	$(LD) $(LDFLAGS) -o secd $^
	if (($(DEBUG) == 0)); then strip $@; fi

clean:
	-rm -f $(CLEANFILES)
	-ls -1 *.lob | grep -v '^compiler\.lob$$' | xargs rm -f

redo: clean all

%.o : %.c
	$(CC) -c $< -o $@

%.o : %.asm
	$(AS) $(ASFLAGS) -o $@ $<

%.lob : %.lso secd
	$(M4) $< | cat compiler.lob - | ./secd > $@
