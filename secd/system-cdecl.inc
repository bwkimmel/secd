; vim: filetype=nasm
; ==============================================================================
; System calls
;
; This version passes parameters on the stack.
; ==============================================================================
;

; ------------------------------------------------------------------------------
; Special file descriptors
;
%define stdin		0
%define stdout		1
%define stderr		2

; ------------------------------------------------------------------------------
; System call numbers
;
%define SYS_exit	1
%define SYS_read	3
%define SYS_write	4

; ==============================================================================
; System call macros
;

; ------------------------------------------------------------------------------
; Issues a system call
; USAGE:  system <call#>
; <call#> = the number identifying the system call to issue
; ------------------------------------------------------------------------------
%macro system 1
	mov		eax, %1
	call	__kernel__
%endmacro

; ------------------------------------------------------------------------------
; Read from a file
; USAGE:  sys.read <fd>, <buf>, <len>
; <fd>  = the file descriptor to read from
; <buf> = the buffer to read into
; <len> = the length of the buffer
; ------------------------------------------------------------------------------
%macro sys.read 3
	push	dword 0
	push	dword %3
	push	dword %2
	push	dword %1
	system	SYS_read	
	add		esp, 16
%endmacro

; ------------------------------------------------------------------------------
; Writes to a file
; USAGE:  sys.write <fd>, <buf>, <len>
; <fd>  = the file descriptor to write to
; <buf> = the buffer to write from
; <len> = the number of bytes to write
; ------------------------------------------------------------------------------
%macro sys.write 3
	push	dword %3
	push	dword %2
	push	dword %1
	system	SYS_write
	add		esp, 12
%endmacro

; ------------------------------------------------------------------------------
; Terminate the process
; USAGE:  sys.exit <errno>
; <errno> = the exit code
; ------------------------------------------------------------------------------
%macro sys.exit 1
	push	dword %1
	system	SYS_exit
	add		esp, 4
%endmacro

; ------------------------------------------------------------------------------
; Kernel system call
;
section .text
align 4
__kernel__:
	int		0x80
	ret

