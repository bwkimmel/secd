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
%define stdin       0
%define stdout      1
%define stderr      2

; ------------------------------------------------------------------------------
; System call numbers
;
%define SYS_exit    1
%define SYS_read    3
%define SYS_write   4
%define SYS_open    5
%define SYS_close   6

%define O_CREAT     0x00000100
%define O_TRUNC     0x00001000
%define O_RDONLY    0x00000000
%define O_WRONLY    0x00000001
%define O_RDWR      0x00000002

; ==============================================================================
; System call macros
;

; ------------------------------------------------------------------------------
; Issues a system call
; USAGE:  system <call#>
; <call#> = the number identifying the system call to issue
; ------------------------------------------------------------------------------
%macro system 1
    mov     eax, %1
    call    __kernel__
%endmacro

; ------------------------------------------------------------------------------
; Read from a file
; USAGE:  sys.read <fd>, <buf>, <len>
; <fd>  = the file descriptor to read from
; <buf> = the buffer to read into
; <len> = the length of the buffer
; ------------------------------------------------------------------------------
%macro sys.read 3
    push    dword 0
    push    dword %3
    push    dword %2
    push    dword %1
    system  SYS_read    
    add     esp, 16
%endmacro

; ------------------------------------------------------------------------------
; Writes to a file
; USAGE:  sys.write <fd>, <buf>, <len>
; <fd>  = the file descriptor to write to
; <buf> = the buffer to write from
; <len> = the number of bytes to write
; ------------------------------------------------------------------------------
%macro sys.write 3
    push    dword %3
    push    dword %2
    push    dword %1
    system  SYS_write
    add     esp, 12
%endmacro

; ------------------------------------------------------------------------------
; Opens a file
; USAGE:  sys.open <filename>, <flags>, <mode>
; <filename> = the name of the file to open
; <flags>    = the file creation flags
; <mode>     = the file access mode
; ------------------------------------------------------------------------------
%macro sys.open 3
    push    dword %3
    push    dword %2
    push    dword %1
    system  SYS_open
    add     esp, 12
%endmacro

; ------------------------------------------------------------------------------
; Closes a file
; USAGE:  sys.close <fd>
; <fd>  = the file descriptor to close
; ------------------------------------------------------------------------------
%macro sys.close 1
    push    dword %1
    system  SYS_close
    add     esp, 4
%endmacro

; ------------------------------------------------------------------------------
; Terminate the process
; USAGE:  sys.exit <errno>
; <errno> = the exit code
; ------------------------------------------------------------------------------
%macro sys.exit 1
    push    dword %1
    system  SYS_exit
    add     esp, 4
%endmacro

; ------------------------------------------------------------------------------
; Kernel system call
;
section .text
align 4
__kernel__:
    int     0x80
    ret

