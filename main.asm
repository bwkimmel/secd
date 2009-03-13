%include 'system.inc'

%define NEWLINE 10

segment .data
	extern	tt_eof, tt_num, tt_alpha, tt_delim, nil

segment .text
	global start
	extern _putchar, _flush, _init_strings, _init, \
		_scan, _putexp, _getexp, _exec, _getexplist

start:
	call	_init_strings
	call	_init
	call	_scan
	call	_getexp
	mov		ebx, eax
	call	_getexplist
	push	eax
	push	ebx
	call	_exec
	add		esp, 8
	push	eax
	call	_putexp
	add		esp, 4
	push	dword NEWLINE
	call	_putchar	
	add		esp, 4
	call	_flush
	push	dword 0
	sys.exit
.halt:
	jmp		.halt

