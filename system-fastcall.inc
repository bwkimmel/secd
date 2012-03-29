; vim: filetype=nasm
; ==============================================================================
; System calls
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
	mov		edx, %3
	mov		ecx, %2
	mov		ebx, %1
	system	SYS_read	
%endmacro

; ------------------------------------------------------------------------------
; Writes to a file
; USAGE:  sys.write <fd>, <buf>, <len>
; <fd>  = the file descriptor to write to
; <buf> = the buffer to write from
; <len> = the number of bytes to write
; ------------------------------------------------------------------------------
%macro sys.write 3
	mov		edx, %3
	mov		ecx, %2
	mov		ebx, %1
	system	SYS_write
%endmacro

; ------------------------------------------------------------------------------
; Terminate the process
; USAGE:  sys.exit <errno>
; <errno> = the exit code
; ------------------------------------------------------------------------------
%macro sys.exit 1
	mov		ebx, %1
	system	SYS_exit
%endmacro

; ------------------------------------------------------------------------------
; Kernel system call
;
section .text
align 4
__kernel__:
	int		0x80
	ret

