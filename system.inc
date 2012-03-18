; vim: filetype=nasm

%define stdin 0
%define stdout 1
%define stderr 2

%define SYS_exit 1
%define SYS_read 3
%define SYS_write 4

%macro system 1
	mov		eax, %1
	call	__kernel__
%endmacro

%macro sys.read 3
	push	dword 0
	push	dword %3
	push	dword %2
	push	dword %1
	system	SYS_read	
	add		esp, 16
%endmacro

%macro sys.write 3
	push	dword %3
	push	dword %2
	push	dword %1
	system	SYS_write
	add		esp, 12
%endmacro

%macro sys.exit 1
	push	dword %1
	system	SYS_exit
	add		esp, 4
%endmacro

section .text
align 4
__kernel__:
	int		0x80
	ret

