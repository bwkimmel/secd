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
	-ls -1 *.lob | grep -iv '^APENDIX2\.LOB$$' | xargs rm -f

redo: clean all

SchemeGrammarMap.lso: BuildSchemeGrammarMap.lob compiler.lob secd
	cat $< | ./secd > $@ 

primitive-compiler.lob: APENDIX2.LOB APENDIX2.LSO secd
	cat APENDIX2.LOB APENDIX2.LSO | ./secd > $@

compiler.lob: compiler.lso primitive-compiler.lob secd
	$(M4) $< | cat primitive-compiler.lob - | ./secd > .temp.$@
	$(M4) $< | cat .temp.$@ - | ./secd > $@
	-rm -f .temp.$@

%.o : %.c
	$(CC) -c $< -o $@

%.o : %.asm
	$(AS) $(ASFLAGS) -o $@ $<

%.lob : %.lso compiler.lob secd
	$(M4) $< | cat compiler.lob - | ./secd > $@
