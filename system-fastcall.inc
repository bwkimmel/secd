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
	mov		edx, %3
	mov		ecx, %2
	mov		ebx, %1
	system	SYS_read	
%endmacro

%macro sys.write 3
	mov		edx, %3
	mov		ecx, %2
	mov		ebx, %1
	system	SYS_write
%endmacro

%macro sys.exit 1
	mov		ebx, %1
	system	SYS_exit
%endmacro

section .text
align 4
__kernel__:
	int		0x80
	ret

