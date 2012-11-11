; ==============================================================================
; SECD machine entry point
; ==============================================================================
;
%include 'system.inc'

%define NEWLINE 10

segment .data
    extern  tt_eof, tt_num, tt_alpha, tt_delim, nil

segment .text
    global _start
    extern _putchar, _flush, _init_strings, _init, \
        _scan, _putexp, _getexp, _exec, _getexplist

; ------------------------------------------------------------------------------
; Entry point
;
_start:
    call    _init_strings       ; initialize string-store
    call    _init               ; initialize SECD machine
    call    _scan
    call    _getexp             ; read SECD object to process
    mov     ebx, eax
    call    _getexplist         ; read expressions to pass to entry function
    push    eax
    push    ebx
    call    _exec               ; pass control to SECD machine
    add     esp, 8
    push    eax
    call    _putexp             ; print resulting expression
    add     esp, 4
    push    dword NEWLINE
    call    _putchar            ; print newline
    add     esp, 4
    call    _flush              ; flush stdout
    sys.exit 0                  ; done
.halt:
    jmp     .halt

