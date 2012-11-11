; ==============================================================================
; Support Functions
;
; This file contains procedures to read and print characters, LispKit Lisp
; tokens and expressions.
; ==============================================================================
;
%include 'system.inc'
%include 'secd.inc'

%define INBUF_SIZE      1024            ; size of read buffer
%define OUTBUF_SIZE     80              ; size of write buffer
%define MAX_TOKEN_SIZE  1024            ; maximum token length

section .data
    global tt_eof, tt_num, tt_alpha, tt_delim
    extern nil

tt_eof      db      "ENDFILE", 0        ; token types
tt_num      db      "NUMERIC", 0
tt_alpha    db      "ALPHANUMERIC", 0
tt_delim    db      "DELIMITER", 0
eof         dd      0                   ; end of file token
outbufind   dd      0                   ; index into write buffer 
open_paren  db      "("
close_paren db      ")"
dot         db      "."
ellipsis    db      "..."               ; Used when printing a recursive expr.
ellips_len  equ     $ - ellipsis

section .bss
inbuf       resb    INBUF_SIZE          ; read buffer
outbuf      resb    OUTBUF_SIZE         ; write buffer
inbufptr    resd    1                   ; index into read buffer
inbufend    resd    1                   ; pointer to end of read buffer
char        resd    1                   ; last character read by _getchar
token       resb    MAX_TOKEN_SIZE      ; last token read by _gettoken
type        resd    1                   ; type of last token read by _gettoken
visited     resb    65536               ; visited flag while printing expr

section .text
    global _putchar, _length, _puttoken, _tostring, _tointeger, \
        _getchar, _gettoken, _isdigit, _isletter, _scan, _isws, \
        _flush, _putexp, _getexp, _getexplist
    extern _flags, _ivalue, _svalue, _car, _cdr, _store, _cons, _symbol, \
        _number

; ------------------------------------------------------------------------------
; Reads an expression from stdin
; EXPECTS token = the initial token
; RETURNS the index of the cons cell at the root of the expression
; ------------------------------------------------------------------------------
_getexp:
    enter   0, 0
    cmp     [token], byte '('
    jne     .elseif
    cmp     [token + 1], byte 0
    jne     .elseif                     ; If next token is '(', then...
        call    _scan                   ; Expression is a cons cell
        call    _getexplist
        jmp     .endif

.elseif:
    cmp     [type], dword tt_num
    jne     .else                       ; If token is a number, then...
        push    dword MAX_TOKEN_SIZE    ; Convert to an integer and allocate a
        push    dword token             ; number cell
        call    _tointeger
        add     esp, 8
        call    _number
        jmp     .endif

.else:                                  ; Otherwise token is a symbol
        push    dword token
        call    _length
        add     esp, 4
        push    eax
        push    dword token
        call    _store                  ; Put in string-store and allocate a
        add     esp, 8                  ; symbol cell
        call    _symbol
    
.endif:
    push    eax
    call    _scan                       ; Scan for next token
    pop     eax
    leave
    ret

; ------------------------------------------------------------------------------
; Reads a list of expressions from stdin
; EXPECTS token = the initial token
; RETURNS eax = the index of the cons cell at the root of a list consisting of
;               all of the expressions read
; ------------------------------------------------------------------------------
_getexplist:
    enter   0, 0
    push    ebx
    call    _getexp                     ; Read the car
    mov     ebx, eax
    cmp     [token], byte '.'
    jne     .elseif 
    cmp     [token + 1], byte 0
    jne     .else                       ; If next token is a dot, then...
        call    _scan                   ; The cdr is a single expression
        call    _getexp
        jmp     .endif      

.elseif:
    cmp     [token], byte ')'
    jne     .else
    cmp     [token + 1], byte 0
    jne     .else                       ; If the next token is ')', then
        mov     eax, dword 0            ; The cdr is NIL
        jmp     .endif

.else:
    call    _getexplist                 ; Neither dot nor ')', cdr is a list

.endif:
    mov     edx, eax                    ; Assemble car and cdr into a cons cell
    mov     eax, ebx
    call    _cons
    pop     ebx
    leave
    ret

; ------------------------------------------------------------------------------
; Prints an expression to stdout
; USAGE: _putexp(<expr>)
; <expr> = the index of a cell containing the expression to print
; ------------------------------------------------------------------------------
_putexp:
    enter   0, 0
    push    ebx
    mov     ebx, [ebp + 8]              ; EBX <-- <expr>
    cmp     [visited + ebx], byte 0
    je      .not_visited
        push    dword ellips_len        ; Already in the process of printing
        push    dword ellipsis          ; the expression we're being asked to
        call    _puttoken               ; print (i.e., it is a recursive
        add     esp, 8                  ; expression), so print an ellipsis and
        pop     ebx                     ; quit.
        leave
        ret
.not_visited:
    mov     [visited + ebx], byte 1     ; Mark visited while printing
    mov     eax, ebx
    call    _flags                      ; Branch depending on type of expression
    test    eax, SECD_ATOM
    jz      .putcons
    and     eax, SECD_TYPEMASK
    cmp     eax, SECD_SYMBOL
    je      .putsym
.putint:                                ; Expression is a number
    mov     eax, ebx
    call    _ivalue                     ; Get the value
    sub     esp, 12
    mov     ebx, esp
    push    ebx
    push    eax
    call    _tostring                   ; Convert it to a string
    add     esp, 8
    push    dword 12
    push    ebx
    call    _puttoken                   ; Print the number
    add     esp, 20 
    jmp     .done
.putsym:                                ; Expression is a symbol
    mov     eax, ebx
    call    _ivalue                     ; Get the address of the string
    mov     ebx, eax
    push    eax
    call    _length                     ; Get the length of the string
    add     esp, 4
    push    eax
    push    ebx
    call    _puttoken                   ; Print the name of the symbol
    add     esp, 8
    jmp     .done
.putcons:                               ; Expression is a cons cell
    push    dword 1
    push    dword open_paren
    call    _puttoken
    add     esp, 8  
.consloop:                              ; Print the car and advance to the cdr,
        mov     eax, ebx                ; continuing as long as the cdr is also
        call    _car                    ; a cons cell.
        push    eax     
        call    _putexp
        add     esp, 4
        mov     eax, ebx
        call    _cdr
        mov     ebx, eax
        call    _flags
        and     eax, SECD_TYPEMASK
        cmp     eax, SECD_CONS
        je      .consloop   
    cmp     eax, SECD_SYMBOL            ; If the last CDR is not NIL, then print
    jne     .cons_dot                   ; dot before printing the CDR, otherwise
    mov     edx, ebx                    ; just print the close parenthesis.
    mov     eax, dword 0
    call    _ivalue
    xchg    eax, ebx
    call    _ivalue
    cmp     eax, ebx    
    je      .cons_end
    mov     ebx, edx
.cons_dot:
    push    dword 1
    push    dword dot
    call    _puttoken                   ; Print the dot
    add     esp, 8
    push    ebx
    call    _putexp                     ; Print the last cdr
    add     esp, 4
.cons_end:                      
    push    dword 1
    push    dword close_paren
    call    _puttoken                   ; Print the close parenthesis
    add     esp, 8
.done:
    mov     ebx, [ebp + 8]
    mov     [visited + ebx], byte 0     ; Done printing.. clear visited flag
    pop     ebx
    leave
    ret

; ------------------------------------------------------------------------------
; Determines if the specified character is a whitespace character
; USAGE: _isws(<char>)
; <char> = the ASCII code of the character to check
; RETURNS non-zero if <char> is a whitespace character, zero otherwise.
; ------------------------------------------------------------------------------
_isws:
    enter   0, 0
    mov     eax, [ebp + 8]              ; EAX <-- <char>
    cmp     eax, 13     ; \n
    je      .true
    cmp     eax, 10     ; \r 
    je      .true
    cmp     eax, 9      ; \t
    je      .true
    cmp     eax, 32     ; space 
    je      .true
    cmp     eax, 0      ; \0
    je      .true
    mov     eax, 0                      ; return 0
    leave
    ret
.true:
    mov     eax, 1                      ; return 1
    leave
    ret

; ------------------------------------------------------------------------------
; Reads a character from stdin and puts it in [char].  If at the end of the
; file, [eof] will be set to 1.
; USAGE: _getchar()
; RETURNS the ASCII code of the character read, or -1 if at the end of the file
; ------------------------------------------------------------------------------
_getchar:
    enter   0, 0
    push    esi
    mov     esi, [inbufptr]             ; First see if the buffer has input
    cmp     esi, [inbufend]             ; available
    jl      .endif
        ; Fill the buffer
        sys.read stdin, inbuf, INBUF_SIZE
        cmp     eax, 0
        je      .eof
        jl      .error
        mov     esi, dword inbuf
        add     eax, esi
        mov     [inbufend], eax
.endif:
    mov     eax, 0                      ; We have a char to return
    mov     al, byte [esi]
    mov     [char], eax
    inc     esi
    mov     [inbufptr], esi
.done:
    pop     esi
    leave
    ret
.error:
.eof:
    mov     eax, -1                     ; End of file
    mov     [eof], dword 1
    jmp     .done

; ------------------------------------------------------------------------------
; Reads a token from stdin.
; USAGE: _gettoken(<buf>,<len>)
; <buf> = the buffer in which to read the token
; <len> = the length of the buffer
; RETURNS the length of the token
; ------------------------------------------------------------------------------
_gettoken:
    enter   0, 0
    push    ebx
    push    edi
    mov     edi, [ebp + 8]              ; EDI <-- <buf>
    mov     ecx, [ebp + 12]             ; ECX <-- <len>
.loop:                                  ; Loop to skip over whitespace
        cmp     dword [eof], 0          ; at end of file?
        jne     .eof
        push    dword [char]
        call    _isws
        add     esp, 4
        cmp     eax, 0
        je      .endloop
        call    _getchar
        jmp     .loop
.endloop:
    mov     ebx, dword [char]           ; EBX <-- first non-whitespace char

    push    ebx                         ; Branch based on first character
    call    _isdigit
    add     esp, 4

    cmp     eax, 0
    jne     .digit                      ; Token is a number
    cmp     ebx, '-'
    je      .dash                       ; Could be symbol or number

    push    ebx
    call    _isletter
    add     esp, 4
    cmp     eax, 0
    jne     .letter                     ; Token is a symbol

    ; Fall through -- token is a delimiter (parenthesis or dot)

.delimiter:                             ; Handle delimiter
    mov     edx, [ebp + 16]
    mov     [edx], dword tt_delim
    mov     byte [edi], bl 
    inc     edi
    call    _getchar    
    jmp     .done
    
.eof:                                   ; Handle end of file
    mov     edx, [ebp + 16]
    mov     [edx], dword tt_eof
    jmp     .done

.dash:                                  ; Handle token beginning with a dash
    mov     byte [edi], bl
    inc     edi
    call    _getchar
    mov     ebx, dword [char]           ; Branch based on second character
    push    ebx
    call    _isletter
    add     esp, 4
    cmp     eax, 0
    jne     .letter                     ; Token is a symbol
    push    ebx
    call    _isdigit
    add     esp, 4
    cmp     eax, 0
    jne     .digit                      ; Token is a number
    jmp     .alpha_endloop              ; End of token: single "-" is a symbol

.digit:                                 ; Handle token beginning with a digit
    mov     byte [edi], bl
    inc     edi
    call    _getchar
    mov     ebx, dword [char]
.digit_loop:                            ; Loop through digits
        push    ebx
        call    _isdigit
        add     esp, 4
        cmp     eax, 0
        je      .digit_endloop
        mov     byte [edi], bl
        inc     edi
        call    _getchar
        mov     ebx, dword [char]
        jmp     .digit_loop
.digit_endloop:
    push    ebx
    call    _isletter                   ; If the token has letters following the
    add     esp, 4                      ; numbers, it is a symbol.
    cmp     eax, 0
    jne     .letter
    mov     edx, [ebp + 16]             ; Otherwise, it's a number
    mov     [edx], dword tt_num
    jmp     .done

.letter:                                ; Handle token beginning with a letter
    mov     byte [edi], bl
    inc     edi
    call    _getchar
    mov     ebx, dword [char]
.alpha_loop:                            ; Read in remaining letters and numbers
        push    ebx
        call    _isletter
        add     esp, 4
        cmp     eax, 0
        jne     .alpha_continue
        push    ebx
        call    _isdigit
        add     esp, 4
        cmp     eax, 0
        je      .alpha_endloop
.alpha_continue:                        ; Hit whitespace or delimieter, we're
        mov     byte [edi], bl          ; done reading the symbol
        inc     edi
        call    _getchar
        mov     ebx, dword [char]
        jmp     .alpha_loop
.alpha_endloop:
    mov     edx, [ebp + 16]
    mov     [edx], dword tt_alpha

.done:
    mov     eax, edi
    sub     eax, [ebp + 8]              ; EAX <-- length of token
    mov     [edi], byte 0
    pop     edi
    pop     ebx
    leave
    ret

; ------------------------------------------------------------------------------
; Scans stdin for the next token
; USAGE: _scan()
; ------------------------------------------------------------------------------
_scan:
    enter   0, 0
    push    dword type
    push    dword MAX_TOKEN_SIZE
    push    dword token
    call    _gettoken
    add     esp, 12
    cmp     [type], dword tt_eof
    jne     .endif
        mov     [type], dword tt_delim
        mov     [token], byte ')'
        mov     [token + 1], byte 0
.endif:
    leave
    ret

; ------------------------------------------------------------------------------
; Determines if character is a digit
; USAGE: _isdigit(<char>)
; <char> = the ASCII code of the character to check
; RETURNS non-zero if <char> is a digit, zero otherwise
; ------------------------------------------------------------------------------
_isdigit:
    enter   0, 0
    mov     eax, [ebp + 8]              ; EAX <-- <char>
    cmp     eax, '0'
    jl      .else                       ; <char> < '0'?
    cmp     eax, '9'
    jg      .else                       ; <char> > '9'?
        mov     eax, 1                  ; return 1
        leave
        ret
.else:
        mov     eax, 0                  ; return 0
        leave
        ret

; ------------------------------------------------------------------------------
; Determines if character is a "letter".  Anything that is not a digit, a dash,
; whitespace, or a delimiter (open or close parenthesis or a dot) is considered
; to be a letter.
; USAGE: _isletter(<char>)
; <char> = the ASCII code of the character to check
; RETURNS non-zero if <char> is a "letter", zero otherwise
; ------------------------------------------------------------------------------
_isletter:
    enter   0, 0
    mov     eax, [ebp + 8]              ; EAX <-- <char>
    push    eax
    call    _isws                       ; Is it a whitespace char?
    add     esp, 4
    cmp     eax, 0
    jne     .false
    mov     eax, [ebp + 8]
    push    eax
    call    _isdigit                    ; Is it a digit?
    add     esp, 4
    cmp     eax, 0
    jne     .false
    mov     eax, [ebp + 8]              ; Check other non-letter characters
    cmp     eax, '('
    je      .false
    cmp     eax, ')'
    je      .false
    cmp     eax, '.'
    je      .false
    cmp     eax, '-'
    je      .false
.true:
    mov     eax, 1                      ; return 1
    leave
    ret
.false:
    mov     eax, 0                      ; return 0
    leave
    ret 

; ------------------------------------------------------------------------------
; Prints a token to stdout
; USAGE: _puttoken(<buf>, <len>)
; <buf> = pointer to token to print
; <len> = the length of the token
; ------------------------------------------------------------------------------
_puttoken:
    enter   0, 0
    push    ebx
    push    esi
    mov     esi, [ebp + 8]              ; ESI <-- <buf>
    mov     ebx, [ebp + 12]             ; EBX <-- <len>
    cmp     ebx, 0
    jle     .done                       ; <len> ≤ 0?
.loop:                                  ; Loop through all chars in the token
        mov     eax, 0
        mov     al, byte [esi]
        cmp     al, 0
        je      .done
        push    ebx
        push    esi
        push    eax
        call    _putchar
        add     esp, 4
        pop     esi
        pop     ebx
        inc     esi                     ; Advance to next char
        dec     ebx                     ; One less to print
        jnz     .loop
.done:
    push    dword ' '                   ; Print single space to separate this
    call    _putchar                    ; token from the next
    add     esp, 4
    pop     esi
    pop     ebx
    leave
    ret

; ------------------------------------------------------------------------------
; Flushes the output buffer to stdout
; USAGE: _flush()
; ------------------------------------------------------------------------------
_flush:
    enter   0, 0
    sys.write stdout, outbuf, [outbufind]
    mov     dword [outbufind], 0
    leave
    ret

; ------------------------------------------------------------------------------
; Prints a character to stdout
; USAGE: _putchar(<char>)
; <char> = the ASCII code of the character to print
; ------------------------------------------------------------------------------
_putchar:
    enter   0, 0
    mov     ecx, [outbufind]            ; Flush the buffer if it's full
    cmp     ecx, OUTBUF_SIZE
    jb      .endif
        sys.write stdout, outbuf, OUTBUF_SIZE
        mov     ecx, 0
.endif:
    mov     eax, [ebp + 8]              ; EAX <-- <char>
    mov     byte [outbuf + ecx], al     ; Add <char> to the output buffer
    inc     ecx
    mov     [outbufind], ecx
    leave
    ret

; ------------------------------------------------------------------------------
; Converts a string to an integer
; USAGE: _tointeger(<buf>, <len>)
; <buf> = pointer to string to convert
; <len> = length of the string to convert
; RETURNS the integer value of the string
; ------------------------------------------------------------------------------
_tointeger:
    enter   0, 0
    push    esi
    push    ebx
    mov     eax, 0
    mov     esi, [ebp + 8]              ; ESI <-- <buf>
    mov     ecx, [ebp + 12]             ; ECX <-- <len>
    mov     edx, 0
    cmp     byte [esi], '-'
    je      .advance                    ; Skip over '-' for now
.loop:
        mov     dl, byte [esi]
        sub     dl, '0'
        jo      .done
        jc      .done
        cmp     dl, '9'
        jg      .done                   ; Break on non-digit
        mov     ebx, eax
        shl     eax, 2
        add     eax, ebx
        shl     eax, 1                  ; EAX <-- EAX * 10
        add     eax, edx                ; EAX <-- EAX + digit
.advance:
        inc     esi
        loop    .loop
.done:
    mov     esi, [ebp + 8]              ; ESI <-- <buf>
    cmp     byte [esi], '-'
    jne     .endif                      ; Negative number?
        neg     eax
.endif:
    pop     ebx
    pop     esi
    leave
    ret

; ------------------------------------------------------------------------------
; Converts a number to a string
; USAGE: _tostring(<num>, <buf>)
; <num> = number to convert
; <buf> = buffer to write string to (must be large enough to hold the result)
; ------------------------------------------------------------------------------
_tostring:
    enter   0, 0
    push    ebx
    push    esi
    push    edi

    mov     eax, [ebp + 8]              ; EAX <-- <num>
    mov     edi, [ebp + 12]             ; EDI <-- <buf>

    cmp     eax, 0
    je      .zero                       ; <num> == 0?
    jl      .negative                   ; <num> < 0?

.start:
    mov     ebx, 10                     ; We are going to be dividing by 10
    mov     esi, esp
    sub     esp, 12
    mov     ecx, 0

.loop:
        mov     edx, 0                  ; Sign extend abs(EAX) into EDX for div
        div     ebx
        add     edx, '0'
        dec     esi
        mov     byte [esi], dl
        inc     ecx
        cmp     eax, 0
        jne     .loop

    cld
    rep     movsb
    add     esp, 12
.done:
    mov     [edi], byte 0
    pop     edi
    pop     esi
    pop     ebx
    leave
    ret

.zero:                                  ; Just write a '0' and exit.
    mov     [edi], byte '0'
    inc     edi
    jmp     .done   

.negative:                              ; Write a '-' and then print -EAX
    neg     eax
    mov     [edi], byte '-'
    inc     edi
    jmp     .start

; ------------------------------------------------------------------------------
; Determines the length of a null-terminated string
; USAGE: _length(<str>)
; <str> = the null-terminated string to compute the length of
; RETURNS the length of the null-terminated string
; ------------------------------------------------------------------------------
_length:
    enter   0, 0
    push    edi
    mov     edx, [ebp + 8]              ; EDX <-- <str>
    mov     edi, edx
    mov     ecx, -1
    mov     eax, 0
    cld
.scan:                                  ; Scan for zero
    scasb
    jnz     .scan
    dec     edi                         ; Compute string length
    mov     eax, edi
    sub     eax, edx
    pop     edi
    leave
    ret 

