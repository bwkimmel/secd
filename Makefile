# define targets here
TARGETS=compiler.lob

CLEANFILES=$(TARGETS) secd *.o

CC=gcc
AS=nasm
ARCH=macho
ASFLAGS=-f $(ARCH)

all: $(TARGETS)

secd: support.o string.o secd.o main.o
	ld -o secd $^

clean:
	-rm -f $(CLEANFILES)

redo: clean all

compiler.lob: APENDIX2.LSO APENDIX2.LOB secd
	cat APENDIX2.LOB APENDIX2.LSO | ./secd > $@	

%.o : %.c
	$(CC) -c $< -o $@

%.o : %.asm
	$(AS) $(ASFLAGS) -o $@ $<

