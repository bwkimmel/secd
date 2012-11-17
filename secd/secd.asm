; ==============================================================================
; SECD machine implementation
;
; This file implements the instruction cycle for an SECD (Stack, Environment,
; Code, Dump) machine.  For details, see:
;
; Peter Henderson, "Functional Programming: Application and Implementation",
; Prentice Hall, 1980.
; ==============================================================================
;
%include 'secd.inc'
%include 'system.inc'


; ==============================================================================
; Constants
;
%define MIN_FREE        5       ; Minimum number of free cells at top of cycle
%define DEDUP_THRESHOLD 1000    ; Attempt dedup if GC yields fewer than this
                                ;   many free cells.

; ==============================================================================
; Flags
;
%define SECD_MARKED     0x80    ; GC-bit for cell array
%define HEAP_MARK       0x01    ; GC-bit for heap items
%define HEAP_FORWARD    0x02    ; Indicates that heap item has been moved


; ==============================================================================
; Reserved registers
;
%define S ebx       ; (S)tack
%define C esi       ; (C)ontrol
%define ff edi      ; Head of the free list (ff)


; ==============================================================================
; Debugging
;
%ifdef DEBUG

; ------------------------------------------------------------------------------
; Displays the error for a bad cell reference and exits.
; ------------------------------------------------------------------------------
_bad_cell_ref:
    sys.write stderr, err_bc, err_bc_len
    sys.exit 1
.halt:
    jmp     .halt

; ------------------------------------------------------------------------------
; Checks that the specified value is a valid cell reference.
; ------------------------------------------------------------------------------
_check_cell_ref:
    enter   0, 0
    cmp     dword [ebp + 8], 0xffff
    ja      _bad_cell_ref
    leave
    ret

%macro check_cell_ref 1
    push    dword %1
    call    _check_cell_ref
    add     esp, 4
%endmacro

%else   ; !DEBUG

%macro check_cell_ref 1
    ; nothing to do
%endmacro

%endif


; ==============================================================================
; Instruction macros
;

; ------------------------------------------------------------------------------
; Save reserved registers for an external function call
; USAGE: pushsecd
; ------------------------------------------------------------------------------
%macro pushsecd 0
    push    S
    push    C
    push    ff
%endmacro

; ------------------------------------------------------------------------------
; Restore reserved registers after an external function call
; USAGE: popsecd
; ------------------------------------------------------------------------------
%macro popsecd 0
    pop     ff
    pop     C
    pop     S
%endmacro

; ------------------------------------------------------------------------------
; Extracts the first element of a cons cell
; USAGE: car <dest>, <src>
; <dest> = the location to put the result into
; <src>  = the cons cell from which to exract the first element
; ------------------------------------------------------------------------------
%macro car 2 
    check_cell_ref %2
    mov     %1, [dword values + %2 * 4]
    shr     %1, 16
%endmacro

; ------------------------------------------------------------------------------
; Extracts the second element of a cons cell
; USAGE: cdr <dest>, <src>
; <dest> = the location to put the result into
; <src>  = the cons cell from which to extract the second element
; ------------------------------------------------------------------------------
%macro cdr 2
    check_cell_ref %2
    mov     %1, [dword values + %2 * 4]
    and     %1, 0xffff
%endmacro

; ------------------------------------------------------------------------------
; Extracts both elements of a cons cell, replacing the source argument with its
; second element.
; USAGE: carcdr <car>, <cdr/src>
; <car>     = the location to put the first element of the cons cell into
; <cdr/src> = the cons cell from which to extract both elements, and the
;             location in which to put the second element
; ------------------------------------------------------------------------------
%macro carcdr 2
    check_cell_ref %2
    mov     %2, [dword values + %2 * 4]
    mov     %1, %2
    shr     %1, 16
    and     %2, 0xffff
%endmacro

; ------------------------------------------------------------------------------
; Extracts both elements of a cons cell, replacing the source argument with its
; first element.
; USAGE: cdrcar <cdr>, <car/src>
; <cdr>     = the location to put the second element of the cons cell into
; <car/src> = the cons cell from which to extract both elements, and the
;             location in which to put the first element
; ------------------------------------------------------------------------------
%macro cdrcar 2
    check_cell_ref %2
    mov     %2, [dword values + %2 * 4]
    mov     %1, %2
    and     %1, 0xffff
    shr     %2, 16
%endmacro

; ------------------------------------------------------------------------------
; Dereferences a cell index
; USAGE: ivalue <dest>
; <dest> = the index into the cell array to dereference, and the location into
;          which to put the value at that location
; ------------------------------------------------------------------------------
%macro ivalue 1
    check_cell_ref %1
    mov     %1, [dword values + %1 * 4]
%endmacro

; ------------------------------------------------------------------------------
; Allocates a cell for a new value
; USAGE: alloc <dest>, <value>, <flags>
; <dest>  = the location in which to put the index of the newly allocated cell
; <value> = the value to place in the new cell
; <flags> = the flags indicating the type of the new cell
; ------------------------------------------------------------------------------
%macro alloc 3
    mov     dword [values + ff * 4], %2
    mov     byte [flags + ff], %3       ; set flags for new cell
    mov     %1, ff
    inc     ff
%endmacro

; ------------------------------------------------------------------------------
; Allocates a new cons cell
; USAGE: cons <car/dest>, <cdr>
; <car/dest> = the location in which to put the index of the new cons cell, and
;              the first element of the new cell
; <cdr>      = the second element of the new cell
; ------------------------------------------------------------------------------
%macro cons 2
    check_cell_ref %1
%ifidni %1,%2
%else
    check_cell_ref %2
%endif
    shl     %1, 16
    or      %1, %2
    alloc   %1, %1, SECD_CONS
%endmacro

; ------------------------------------------------------------------------------
; Allocates a new number cell
; USAGE: number <dest>, <value>
; <dest>  = the location in which to put the index of the new cell
; <value> = the numeric value to place in the new cell
; ------------------------------------------------------------------------------
%macro number 2
    alloc   %1, %2, SECD_NUMBER
%endmacro

; ------------------------------------------------------------------------------
; Allocates a new symbolic cell
; USAGE: symbol <dest>, <value>
; <dest>  = the location in which to put the index of the new cell
; <value> = the address of the symbol in the string store
; ------------------------------------------------------------------------------
%macro symbol 2
    alloc   %1, %2, SECD_SYMBOL
%endmacro

; ------------------------------------------------------------------------------
; Tests if the indicate cell is a number cell.  If it is, ZF will be clear,
; otherwise ZF will be set.
; USAGE: isnumber <cell>
; <cell> = the cell to test
; ------------------------------------------------------------------------------
%macro isnumber 1
    check_cell_ref %1
    test    byte [flags + %1], 0x02
%endmacro

; ------------------------------------------------------------------------------
; Checks if the arguments are suitable for arithmetic operations.  If they are
; not, control will jump to "_arith_nonnum", which will push NIL onto the stack
; and return control to the top of the instruction cycle.
; USAGE: check_arith_args <arg1>, <arg2>
; <arg1> = the first argument
; <arg2> = the second argument
; ------------------------------------------------------------------------------
%macro check_arith_args 2
    isnumber %1
    jz      _arith_nonnum
    isnumber %2
    jz      _arith_nonnum
%endmacro


; ==============================================================================
; Builtin strings
;
segment .data
magic       db      "SECD", 0, 0
magic_len   equ     $ - magic
tstr        db      "T"
tstr_len    equ     $ - tstr
fstr        db      "F"
fstr_len    equ     $ - fstr
nilstr      db      "NIL"
nilstr_len  equ     $ - nilstr
err_ii      db      "Illegal instruction", 10
err_ii_len  equ     $ - err_ii
err_mem     db      "Memory error", 10
err_mem_len equ     $ - err_mem
err_hf      db      "Out of heap space", 10
err_hf_len  equ     $ - err_hf
err_car     db      "Attempt to CAR an atom", 10
err_car_len equ     $ - err_car
err_cdr     db      "Attempt to CDR an atom", 10
err_cdr_len equ     $ - err_cdr
err_oob     db      "Index out of bounds", 10
err_oob_len equ     $ - err_oob

%ifdef DEBUG
err_ff      db      "Free cells in use", 10
err_ff_len  equ     $ - err_ff
err_bc      db      "Bad cell reference", 10
err_bc_len  equ     $ - err_bc
%endif

sep         db      10, "-----------------", 10
sep_len     equ     $ - sep
maj_sep     db      10, "==============================================", 10
maj_sep_len equ     $ - maj_sep
gcheap      db      0

dump_file   db      "dump.bin", 0
err_dmp     db      "Can't open dump file", 10
err_dmp_len equ     $ - err_dmp


; ==============================================================================
; Storage for cells
;
; Each cell consists of a 32-bit value and an 8-bit set of flags.  The format of
; the cell is determined by the flags from the table below
;
; TYPE     DATA                                   FLAGS
; Cons     [31.....CAR.....16|15.....CDR......0]  x000 x000
; Symbol   [31............POINTER.............0]  x000 x001
; Number   [31.............VALUE..............0]  x000 x011
;                                                 ^---------- GC-bit
;
; For a cons cell, the CAR and the CDR are 16-bit indices into the cell array.
;
segment .bss
values      resd    65536   ; Storage for cons cells and ivalues
values2     resd    65536
flags       resb    65536   ; Storage for isatom and isnumber bits


; ==============================================================================
; SECD-machine registers stored in memory
;
E           resd    1       ; (E)nvironment register
D           resd    1       ; (D)ump register
true        resd    1       ; true register
false       resd    1       ; false register
Sreg        resd    1
Creg        resd    1
ffreg       resd    1

mark        resd    1

; ==============================================================================
; SECD-machine code
; ==============================================================================
segment .text
    global _exec, _flags, _car, _cdr, _ivalue, _issymbol, _isnumber, \
        _iscons, _cons, _svalue, _init, _number, _symbol
    extern _store, _getchar, _putchar, _putexp, _flush, \
        _heap_alloc, _heap_mark, _heap_sweep, _heap_forward, \
        _heap_item_length

; ==============================================================================
; Exported functions
;

_dumpimage:
    call    _gc

    push    eax         ; Save current SECD-machine state
    push    ecx
    push    edx
    push    S
    push    C

    mov     [Sreg], dword S
    mov     [Creg], dword C
    mov     [ffreg], dword ff
    sys.open dump_file, O_CREAT|O_TRUNC|O_WRONLY, 0q644
    cmp     eax, 0
    jge     .endif
  
        call    _flush
        sys.write stderr, err_dmp, err_dmp_len
        sys.exit 1
.stop:
        jmp     .stop
     
.endif:
    push    eax
    sys.write [esp], magic, magic_len
    sys.write [esp], Sreg, 2
    sys.write [esp], E, 2
    sys.write [esp], Creg, 2
    sys.write [esp], D, 2
    sys.write [esp], ffreg, 2

    mov     eax, dword [ffreg]
    shl     eax, 2
    sys.write [esp], values, eax
    sys.write [esp], flags, dword [ffreg]
    sys.close [esp]
    add     esp, 4

    pop     C           ; Restore SECD-machine state
    pop     S
    pop     edx
    pop     ecx
    pop     eax
    ret

; ------------------------------------------------------------------------------
; Prints the current state of the machine for diagnostic purposes
;
_dumpstate:
    sys.write stdout, maj_sep, maj_sep_len
    push    dword S
    call    _putexp
    add     esp, 4
    call    _flush
    sys.write stdout, sep, sep_len

    push    dword [E]
    call    _putexp
    add     esp, 4
    call    _flush
    sys.write stdout, sep, sep_len
    
    push    C
    call    _putexp
    add     esp, 4
    call    _flush
    ret

_car:
    car     eax, eax
    ret

_cdr:
    cdr     eax, eax
    ret

_ivalue:
    ivalue  eax
    ret

_svalue:
    ivalue  eax
    ret

_cons:
    xchg    ff, [ffreg]
    cons    eax, edx
    xchg    ff, [ffreg]
    ret

_number:
    xchg    ff, [ffreg]
    number  eax, eax
    xchg    ff, [ffreg]
    ret

_symbol:
    xchg    ff, [ffreg]
    symbol  eax, eax
    xchg    ff, [ffreg]
    ret

_flags:
    mov     al, byte [flags + eax]
    and     eax, 0x000000ff
    ret

_issymbol:
    call    _flags
    and     eax, SECD_TYPEMASK
    cmp     eax, SECD_SYMBOL
    sete    al  
    ret

_isnumber:
    call    _flags
    and     eax, SECD_TYPEMASK
    cmp     eax, SECD_NUMBER
    sete    al
    ret

_iscons:
    call    _flags
    and     eax, SECD_TYPEMASK
    cmp     eax, SECD_CONS
    sete    al
    ret

_init:
    enter   0, 0
    mov     ff, 1
    push    dword tstr_len
    push    dword tstr
    call    _store
    add     esp, 8
    symbol  eax, eax
    mov     [true], eax
    push    dword fstr_len
    push    dword fstr
    call    _store
    add     esp, 8
    symbol  eax, eax
    mov     [false], eax
    push    dword nilstr_len
    push    dword nilstr
    call    _store
    add     esp, 8
    mov     byte [flags], SECD_SYMBOL
    mov     dword [values], eax
    mov     [ffreg], ff

;    call    _test_dedup
;    sys.exit 1

    leave
    ret

_exec:
    enter   0, 0
    push    ebx
    push    esi
    push    edi
    mov     ff, [ffreg]
    mov     C, [ebp + 8]    ; C <-- fn
    and     C, 0xffff
    mov     S, [ebp + 12]   ; S <-- args
    and     S, 0xffff
    mov     [E], dword 0
    mov     [D], dword 0
    cons    S, 0
    ;
    ; ---> to top of instruction cycle ...

;    call    _test_dedup

    call    _dumpimage
    ;call    _dumpstate
;    sys.exit 1
    

; ==============================================================================
; Top of SECD Instruction Cycle
;
_cycle:
    cmp     ff, 0x10000 - MIN_FREE
    jbe     .nogc
    cmp     ff, 0x10000
    ja      _memerror
    call    _gc
    cmp     ff, 0x10000 - MIN_FREE
    ja      _out_of_space
.nogc:
    check_cell_ref dword S              ; Check that all registers are valid
    check_cell_ref dword [E]            ; cell references
    check_cell_ref dword C
    check_cell_ref dword [D]
    check_cell_ref dword ff
    carcdr  eax, C                      ; Pop next instruction from code list
    ivalue  eax                         ; Get its numeric value
    cmp     eax, dword numinstr         ; Check that it is a valid opcode
    jae     _illegal
    jmp     [dword _instr + eax * 4]    ; Jump to opcode handler

_illegal:
    call    _flush
    sys.write stderr, err_ii, err_ii_len
    sys.exit 1
.stop:
    jmp     .stop
    
_memerror:
    call    _flush
    sys.write stderr, err_mem, err_mem_len
    sys.exit 1
.stop:
    jmp     .stop

_out_of_space:
    call    _flush
    sys.write stderr, err_hf, err_hf_len
    sys.exit 1
.halt:
    jmp     .halt


; ==============================================================================
; SECD Instruction Set
;
; The first 21 instructions (LD - STOP) come directly from Henderson's book.
; The remainder are extensions.
;
; Summary (from Sec. 6.2 of Henderson (1980)):
;   LD   - Load (from environment)
;   LDC  - Load constant
;   LDF  - Load function
;   AP   - Apply function
;   RTN  - Return
;   DUM  - Create dummy environment
;   RAP  - Recursive apply
;   SEL  - Select subcontrol
;   JOIN - Rejoin main control
;   CAR  - Take car of item on top of stack
;   CDR  - Take cdr of item on top of stack
;   ATOM - Apply atom predicate to top stack item
;   CONS - Form cons of top two stack items
;   EQ   - Apply eq predicate to top two stack items
;   ADD  - \
;   SUB  - |
;   MUL  - \_ Apply arithmetic operation to top two stack items
;   DIV  - /
;   REM  - |
;   LEQ  - /
;   STOP - Stop
;
; Extensions:
;   NOP  - No operation
;   SYM  - Apply issymbol predicate to top stack item
;   NUM  - Apply isnumber predicate to top stack item
;   GET  - Push ASCII value of a character from stdin onto stack
;   PUT  - Pop ASCII value from stack and write it to stdout
;   APR  - Apply and return (for tail-call optimization)
;   TSEL - Tail-select (for IF statement in tail position)
;   MULX - Extended multiply (returns a pair representing 64-bit result)
;   PEXP - Print expression on top of stack to stdout
;   POP  - Pop an item off of the stack
;
; The following are not yet fully implemented:
;   CVEC - Create vector
;   VSET - Set element of vector
;   VREF - Get element of vector
;   VLEN - Get length of vector
;   VCPY - Bulk copy between vectors
;   CBIN - Create binary blob
;   BSET - Set byte in binary blob
;   BREF - Get byte in binary blob
;   BLEN - Get size of binary blob
;   BCPY - Bulk copy between binary blobs
;   BS16 - Set 16-bit value in binary blob
;   BR16 - Get 16-bit value in binary blob
;   BS32 - Set 32-bit value in binary blob
;   BR32 - Get 32-bit value in binary blob
;
_instr \
    dd  _instr_NOP , \
        _instr_LD  , _instr_LDC , _instr_LDF , _instr_AP  , _instr_RTN , \
        _instr_DUM , _instr_RAP , _instr_SEL , _instr_JOIN, _instr_CAR , \
        _instr_CDR , _instr_ATOM, _instr_CONS, _instr_EQ  , _instr_ADD , \
        _instr_SUB , _instr_MUL , _instr_DIV , _instr_REM , _instr_LEQ , \
        _instr_STOP, _instr_SYM , _instr_NUM , _instr_GET , _instr_PUT , \
        _instr_APR , _instr_TSEL, _instr_MULX, _instr_PEXP, _instr_POP, \
        _instr_CVEC, _instr_VSET, _instr_VREF, _instr_VLEN, _instr_VCPY, \
        _instr_CBIN, _instr_BSET, _instr_BREF, _instr_BLEN, _instr_BCPY, \
        _instr_BS16, _instr_BR16, _instr_BS32, _instr_BR32

numinstr    equ     ($ - _instr) >> 2
    

; ==============================================================================
; SECD Instruction Implementations
;

; ------------------------------------------------------------------------------
; NOP - No operation
;
; TRANSITION:  s e (NOP.c) d  -->  s e c d
; ------------------------------------------------------------------------------
_instr_NOP:
    jmp     _cycle

; ------------------------------------------------------------------------------
; POP - Pop item off of the stack
;
; TRANSITION:  (x.s) e (POP.c) d  -->  s e c d
; ------------------------------------------------------------------------------
_instr_POP:
    cdr     S, S
    jmp     _cycle

; ------------------------------------------------------------------------------
; LD - Load (from environment)
;
; TRANSITION:  s e (LD i.c) d  -->  (x.s) e c d
;              where x = locate(i,e)
; ------------------------------------------------------------------------------
_instr_LD:
    mov     eax, [E]    ; W <-- E
    carcdr  edx, C      ; EDX <-- car(cdr(C)), C' <-- cdr(cdr(C))

    carcdr  ecx, edx    ; ECX <-- car(car(cdr(C))), EDX <-- cdr(car(cdr(C)))
    ivalue  ecx
    jcxz    .endloop1
.loop1:                 ; FOR i = 1 TO car(car(cdr(C)))
        cdr     eax, eax    ; W <-- cdr(W)
        loop    .loop1
.endloop1:

    car     eax, eax    ; W <-- car(W)
    mov     ecx, edx    ; ECX <-- cdr(car(cdr(C)))
    ivalue  ecx
    jcxz    .endloop2
.loop2:                 ; FOR i = 1 TO cdr(car(cdr(C)))
        cdr     eax, eax    ; W <-- cdr(W)
        loop    .loop2
.endloop2:

    car     eax, eax    ; W <-- car(W)
    cons    eax, S
    mov     S, eax      ; S <-- cons(W, S)
    jmp     _cycle
    
; ------------------------------------------------------------------------------
; LDC - Load constant
;
; TRANSITION:  s e (LDC x.c) d  --> (x.s) e c d
; ------------------------------------------------------------------------------
_instr_LDC:
    carcdr  eax, C
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; LDF - Load function
;
; TRANSITION:  s e (LDF c'.c) d  --> ((c'.e).s) e c d 
; ------------------------------------------------------------------------------
_instr_LDF:
    carcdr  eax, C
    cons    eax, [E]
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; AP - Apply function
;
; TRANSITION:  ((c'.e') v.s) e (AP.c) d  -->  NIL (v.e') c' (s e c.d)
; ------------------------------------------------------------------------------
_instr_AP:
    cons    C, [D]
    mov     eax, [E]
    cons    eax, C      ; EAX <-- cons(E, cons(cdr(C), D))
    carcdr  edx, S      ; EDX <-- car(S), S' <-- cdr(S)
    carcdr  C, edx      ; C' <-- car(car(S)), EDX <-- cdr(car(S))
    carcdr  ecx, S      ; ECX <-- car(cdr(S)), S' <-- cdr(cdr(S))
    cons    S, eax
    mov     [D], S      ; D' <-- cons(cdr(cdr(S)), cons(e, cons(cdr(c), d)))
    cons    ecx, edx
    mov     [E], ecx    ; E' <-- cons(car(cdr(S)), cdr(car(S)))
    mov     S, 0        ; S' <-- nil
    jmp     _cycle

; ------------------------------------------------------------------------------
; RTN - Return
;
; TRANSITION:  (x) e' (RTN) (s e c.d)  -->  (x.s) e c d
; ------------------------------------------------------------------------------
_instr_RTN:
    mov     edx, [D]
    carcdr  eax, edx    ; EAX <-- car(D), EDX <-- cdr(D)
    car     S, S
    cons    S, eax      ; S' <-- cons(car(S), car(D))
    carcdr  eax, edx    ; EAX <-- car(cdr(D)), EDX <-- cdr(cdr(D))
    mov     [E], eax    ; E' <-- car(cdr(D))
    carcdr  C, edx      ; C' <-- car(cdr(cdr(D))), EDX <-- cdr(cdr(cdr(D)))
    mov     [D], edx    ; D' <-- cdr(cdr(cdr(D)))
    jmp     _cycle
    
; ------------------------------------------------------------------------------
; DUM - Create dummy environment
;
; TRANSITION:  s e (DUM.c) d  -->  s (Ω.e) c d
; ------------------------------------------------------------------------------
_instr_DUM:
    mov     eax, 0
    cons    eax, [E]
    mov     [E], eax    ; E' <-- cons(nil, E)
    jmp     _cycle
    
; ------------------------------------------------------------------------------
; RAP - Recursive apply
;
; TRANSITION:  ((c'.e') v.s) (Ω.e) (RAP.c) d  -->  NIL rplaca(e',v) c' (s e c.d)
; ------------------------------------------------------------------------------
_instr_RAP:
    cons    C, [D]      ; C' <-- cons(cdr(C), D)
    mov     edx, [E]
    carcdr  eax, edx    ; EAX <-- car(E), EDX <-- cdr(E)
    cons    eax, C      ; EAX <-- cons(cdr(E), cons(cdr(C), D))
    carcdr  edx, S      ; EDX <-- car(S), S' <-- cdr(S)
    carcdr  C, edx      ; C' <-- car(car(S)), EDX <-- cdr(car(S))
    mov     [E], edx    ; E' <-- EDX = cdr(car(S))
    carcdr  ecx, S      ; ECX <-- car(cdr(S)), S' <-- cdr(cdr(S))
    cons    S, eax      ; D' <-- cons(cdr(cdr(S)),
    mov     [D], S      ;             cons(cdr(E), cons(cdr(C), D)))
    
    ; car(EDX) <-- ECX, S used as temporary register
    mov     S, [dword values + edx * 4]
    and     S, 0x0000ffff
    shl     ecx, 16
    or      S, ecx
    mov     [dword values + edx * 4], S

    mov     S, 0        ; S' <-- nil

    cons    eax, C      ; EAX <-- cons(cdr(E)
    
    jmp     _cycle

; ------------------------------------------------------------------------------
; SEL - Select subcontrol
;
; TRANSITION:  (x.s) e (SEL ct cf.c) d  -->  s e c' (c.d)
;              where c' = ct if x = T, and c' = cf if x = F
; ------------------------------------------------------------------------------
_instr_SEL:
    mov     eax, C
    carcdr  edx, eax    ; EDX <-- car(cdr(C))
    carcdr  ecx, eax    ; ECX <-- car(cdr(cdr(C)), EAX <-- cdr(cdr(cdr(C)))
    cons    eax, [D]    
    mov     [D], eax    ; D' <-- cons(cdr(cdr(cdr(C))), D)  
    carcdr  eax, S      ; EAX <-- car(S), S' <-- cdr(S)
    push    S
    mov     S, [true]
    ivalue  S   
    ivalue  eax
    cmp     eax, S 
    cmove   C, edx      ; IF car(S) == true THEN C' <-- car(cdr(C))
    cmovne  C, ecx      ; IF car(S) != true THEN C' <-- car(cdr(cdr(C)))
    pop     S
    jmp     _cycle

; ------------------------------------------------------------------------------
; JOIN - Rejoin main control
;
; TRANSITION:  s e (JOIN) (c.d)  -->  s e c d
; ------------------------------------------------------------------------------
_instr_JOIN:
    mov     eax, [D]
    carcdr  C, eax
    mov     [D], eax 
    jmp     _cycle

; ------------------------------------------------------------------------------
; CAR - Take car of item on top of stack
;
; TRANSITION:  ((a.b) s) e (CAR.c) d  -->  (a.s) e c d
; ------------------------------------------------------------------------------
_instr_CAR:
    cdrcar  eax, S
    mov     dl, byte [flags + S]
    test    dl, SECD_ATOM
    jz      .endif
        call    _flush
        sys.write stderr, err_car, err_car_len
        sys.exit 1
.halt:
        jmp     .halt
.endif:
    car     S, S
    cons    S, eax 
    jmp     _cycle
    
; ------------------------------------------------------------------------------
; CDR - Take cdr of item on top of stack
;
; TRANSITION:  ((a.b) s) e (CAR.c) d  -->  (b.s) e c d
; ------------------------------------------------------------------------------
_instr_CDR:
    cdrcar  eax, S
    mov     dl, byte [flags + S]
    test    dl, SECD_ATOM
    jz      .endif
        call    _flush
        sys.write stderr, err_cdr, err_cdr_len
        sys.exit 1
.halt:
        jmp     .halt
.endif:
    cdr     S, S
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; ATOM - Apply atom predicate to top stack item
;
; TRANSITION:  (a.s) e (ATOM.c) d  -->  (t.s) e c d
;              where t = T if a is an atom and t = F if a is not an atom.
; ------------------------------------------------------------------------------
_instr_ATOM:
    carcdr  eax, S      ; EAX <-- car(S), S' <-- cdr(S)
    mov     dl, byte [flags + eax]
                        ; DL <-- flags for EAX = car(S)
    test    dl, SECD_ATOM 
    cmovnz  eax, [true]     ; IF (isnumber OR issymbol) THEN EAX <-- true
    cmovz   eax, [false]    ; IF (!isnumber AND !issymbol) THEN EAX <-- false
    cons    eax, S
    mov     S, eax      ; S' <-- cons(true/false, cdr(S))
    jmp     _cycle

; ------------------------------------------------------------------------------
; CONS - Form cons of top two stack items
;
; TRANSITION:  (a b.s) e (CONS.c) d  -->  ((a.b).s) e c d
; ------------------------------------------------------------------------------
_instr_CONS:
    cdrcar  edx, S
    carcdr  eax, edx    ; EAX = car(cdr(S)), EDX = cdr(cdr(S)), S' = car(S)
    cons    S, eax
    cons    S, edx
    jmp     _cycle
    
; ------------------------------------------------------------------------------
; EQ - Apply eq predicate to top two stack items
;
; TRANSITION:  (a b.s) e (EQ.c) d  -->  ([a=b].s) e c d
; ------------------------------------------------------------------------------
_instr_EQ:
    carcdr  eax, S      ; EAX <-- car(S), S' <-- cdr(S)
    mov     dl, byte [flags + eax]
    carcdr  ecx, S      ; ECX <-- car(cdr(S)), S' <-- cdr(cdr(S))
    mov     dh, byte [flags + ecx]
    
    and     dx, 0x0101
    cmp     dx, 0x0101
    jne     .else
    ivalue  eax
    ivalue  ecx
    cmp     eax, ecx
    jne     .else       ; IF isatom(car(S)) AND isatom(car(cdr(S))) AND
                        ;    ivalue(car(S)) == ivalue(car(cdr(S))) THEN ...
        mov     eax, [true]
        jmp     .endif
.else:
        mov     eax, [false]
.endif:
    cons    eax, S
    mov     S, eax      ; S' <-- cons(T/F, cdr(cdr(S)))
    jmp     _cycle

; ------------------------------------------------------------------------------
; Arithmetic operation on non-numeric operands - push NIL onto stack as the
; result of this operation and jump to the top of the instruction cycle
; 
_arith_nonnum:
    mov     eax, 0
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; ADD - Add top two stack items
;
; TRANSITION:  (a b.s) e (ADD.c) d  -->  ([a+b].s) e c d
; ------------------------------------------------------------------------------
_instr_ADD:
    carcdr  edx, S
    carcdr  eax, S      ; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
    check_arith_args eax, edx
    ivalue  eax
    ivalue  edx
    add     eax, edx
    number  eax, eax
    cons    eax, S
    mov     S, eax
    jmp     _cycle
    
; ------------------------------------------------------------------------------
; SUB - Subtract top two stack items
;
; TRANSITION:  (a b.s) e (SUB.c) d  -->  ([a-b].s) e c d
; ------------------------------------------------------------------------------
_instr_SUB:
    carcdr  edx, S
    carcdr  eax, S      ; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
    check_arith_args eax, edx
    ivalue  eax
    ivalue  edx
    sub     eax, edx
    number  eax, eax
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; MUL - Multiply top two stack items
;
; TRANSITION:  (a b.s) e (MUL.c) d  -->  ([a*b].s) e c d
; ------------------------------------------------------------------------------
_instr_MUL:
    carcdr  edx, S
    carcdr  eax, S      ; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
    check_arith_args eax, edx
    ivalue  eax
    ivalue  edx
    imul    edx
    number  eax, eax
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; MUL - Extended multiply top two stack items
;
; TRANSITION:  (a b.s) e (MULX.c) d  -->  ((lo.hi).s) e c d
;              where lo is the least significant 32-bits of a*b and hi is the
;              most significant 32-bits of a*b
; ------------------------------------------------------------------------------
_instr_MULX:
    carcdr  edx, S
    carcdr  eax, S      ; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
    check_arith_args eax, edx
    ivalue  eax
    ivalue  edx
    imul    edx
    number  eax, eax
    number  edx, edx
    cons    eax, edx
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; DIV - Divide top two stack items
;
; TRANSITION:  (a b.s) e (DIV.c) d  -->  ([a/b].s) e c d
; ------------------------------------------------------------------------------
_instr_DIV:
    carcdr  ecx, S
    carcdr  eax, S      ; EAX = car(cdr(S)), ECX = car(S), S' = cdr(cdr(S))
    check_arith_args eax, ecx
    ivalue  eax
    ivalue  ecx
    cdq                 ; Extend sign of EAX into all bits of EDX
    idiv    ecx         ; Compute EAX <-- EDX:EAX / ECX
    number  eax, eax
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; REM - Compute the remainder resulting from the division of the top two stack
;       items
;
; TRANSITION:  (a b.s) e (REM.c) d  -->  ([a%b].s) e c d
; ------------------------------------------------------------------------------
_instr_REM:
    carcdr  ecx, S
    carcdr  eax, S      ; EAX = car(cdr(S)), ECX = car(S), S' = cdr(cdr(S))
    check_arith_args eax, ecx
    ivalue  eax
    ivalue  ecx
    mov     edx, eax
    sar     edx, 31     ; Extend sign of EAX into all bits of EDX
    idiv    ecx         ; Compute EDX <-- EDX:EAX % ECX
    number  edx, edx
    cons    edx, S
    mov     S, edx
    jmp     _cycle

; ------------------------------------------------------------------------------
; LEQ - Test whether the top stack item is less than or equal to the second item
;       on the stack
;
; TRANSITION:  (a b.s) e (REM.c) d  -->  ([a≤b].s) e c d
; ------------------------------------------------------------------------------
_instr_LEQ:
    carcdr  edx, S
    carcdr  eax, S      ; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
    mov     cl, byte [flags + edx]
    and     cl, SECD_TYPEMASK
    mov     ch, byte [flags + eax]
    and     ch, SECD_TYPEMASK
    cmp     ch, cl      ; First compare types
    jne     .result     ; If they have different types, we have a result, else..
    ivalue  eax
    ivalue  edx
    cmp     eax, edx    ; Compare their values
.result:
    cmovle  eax, [true]
    cmovnle eax, [false]
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; STOP - Halt the machine
;
; TRANSITION:  s e (STOP) d  -->  <undefined>
; ------------------------------------------------------------------------------
_instr_STOP:
    car     S, S
;    call    _dumpimage
    mov     eax, S
    pop     edi
    pop     esi
    pop     ebx
    leave
    ret

; ------------------------------------------------------------------------------
; SYM - Apply issymbol predicate to top stack item
;
; TRANSITION:  (x.s) e (SYM.c) d  -->  (t.s) e c d
;              where t = T if x is a symbol, and t = F if x is not a symbol
; ------------------------------------------------------------------------------
_instr_SYM:
    carcdr  eax, S      ; EAX <-- car(S), S' <-- cdr(S)
    mov     dl, byte [flags + eax]
                        ; DL <-- flags for EAX = car(S)
    and     dl, SECD_TYPEMASK
    cmp     dl, SECD_SYMBOL
    cmove   eax, [true]     ; IF (issymbol) THEN EAX <-- true
    cmovne  eax, [false]    ; IF (!issymbol) THEN EAX <-- false
    cons    eax, S
    mov     S, eax      ; S' <-- cons(true/false, cdr(S))
    jmp     _cycle

; ------------------------------------------------------------------------------
; NUM - Apply isnumber predicate to top stack item
;
; TRANSITION:  (x.s) e (NUM.c) d  -->  (t.s) e c d
;              where t = T if x is a number, and t = F if x is not a number
; ------------------------------------------------------------------------------
_instr_NUM:
    carcdr  eax, S      ; EAX <-- car(S), S' <-- cdr(S)
    mov     dl, byte [flags + eax]
                        ; DL <-- flags for EAX = car(S)
    and     dl, SECD_TYPEMASK
    cmp     dl, SECD_NUMBER
    cmove   eax, [true]     ; IF (isnumber) THEN EAX <-- true
    cmovne  eax, [false]    ; IF (!isnumber) THEN EAX <-- false
    cons    eax, S
    mov     S, eax      ; S' <-- cons(true/false, cdr(S))
    jmp     _cycle

; ------------------------------------------------------------------------------
; GET - Push ASCII value of a character from stdin onto stack
;
; TRANSITION:  s e (GET.c) d  -->  (x.s) e c d
;              where x is the ASCII value of the character read from stdin
; ------------------------------------------------------------------------------
_instr_GET:
    pushsecd
    call    _getchar
    popsecd
    number  eax, eax
    cons    eax, S
    mov     S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; PUT - Pop ASCII value from stack and write it to stdout
;
; TRANSITION:  (x.s) e (PUT.c) d  -->  s e c d
; SIDE EFFECT:  The character with the ASCII value x is printed to stdout
; ------------------------------------------------------------------------------
_instr_PUT:
    car     eax, S
    ivalue  eax
    and     eax, 0x000000ff
    pushsecd
    push    eax
    call    _putchar
    add     esp, 4
    popsecd
    jmp     _cycle

; ------------------------------------------------------------------------------
; PEXP - Print expression on top of stack to stdout
;
; TRANSITION:  (x.s) e (PEXP.c) d  -->  (x.s) e c d
; SIDE EFFECT:  The expression x is printed to stdout
; ------------------------------------------------------------------------------
_instr_PEXP:
    car     eax, S
    pushsecd
    push    eax
    call    _putexp
    add     esp, 4
    popsecd
    jmp     _cycle

; ------------------------------------------------------------------------------
; APR - Apply and return (for tail-call optimization)
;
; Note that the only difference between the transition for APR and the that of
; AP is that the dump register is left untouched.  Hence, the effect of RTN will
; be to return control to the current function's caller rather than to this
; function.
;
; TRANSITION:  ((c'.e') v.s) e (APR) d  -->  NIL (v.e') c' d
; ------------------------------------------------------------------------------
_instr_APR:
    carcdr  edx, S      ; EDX <-- car(S), S' <-- cdr(S)
    carcdr  C, edx      ; C' <-- car(car(S)), EDX <-- cdr(car(S))
    car     ecx, S      ; ECX <-- car(cdr(S))
    cons    ecx, edx
    mov     [E], ecx    ; E' <-- cons(car(cdr(S)), cdr(car(S)))
    mov     S, 0        ; S' <-- nil
    jmp     _cycle

; ------------------------------------------------------------------------------
; TSEL - Tail-select (for IF statement in tail position)
;
; Note that the only difference between the transition for TSEL and the that of
; SEL is that the dump register is left untouched.  Hence, JOIN should not be
; used at the end of ct or cf, as this would result in undefined behavior.
; Instead, a RTN instruction should be encountered at the end of ct or cf.
;
; TRANSITION:  (x.s) e (TSEL ct cf) d  -->  s e c' d
;              where c' = ct if x = T, and c' = cf if x = F
; ------------------------------------------------------------------------------
_instr_TSEL:
    mov     eax, C
    carcdr  edx, eax    ; EDX <-- car(cdr(C))
    car     ecx, eax    ; ECX <-- car(cdr(cdr(C))
    carcdr  eax, S      ; EAX <-- car(S), S' <-- cdr(S)
    push    S
    mov     S, [true]
    ivalue  S   
    ivalue  eax
    cmp     eax, S 
    cmove   C, edx      ; IF car(S) == true THEN C' <-- car(cdr(C))
    cmovne  C, ecx      ; IF car(S) != true THEN C' <-- car(cdr(cdr(C)))
    pop     S
    jmp     _cycle

; ------------------------------------------------------------------------------
; CVEC - Create vector
;
; TRANSITION:  (n.s) e (CVEC.c) d  -->  (v.s) e c d
;              where v is a newly allocated vector of length n
; ------------------------------------------------------------------------------
_instr_CVEC:
    carcdr  eax, S      ; EAX <-- number of elements in vector
    ivalue  eax
    shl     eax, 1      ; EAX <-- 2*length == # bytes to allocate
    call    _malloc
    alloc   eax, eax, SECD_VECTOR
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; VSET - Set element of vector
;
; TRANSITION:  (v i x.s) e (VSET.c) d  -->  (v.s) e c d
; SIDE EFFECT:  v[i] <-- x
; ------------------------------------------------------------------------------
_instr_VSET:
    carcdr  eax, S
    carcdr  ecx, S
    push    eax
    ivalue  eax 
    ivalue  ecx
    mov     edx, eax
    call    _heap_item_length   ; Does not clobber ECX, EDX
    shr     eax, 1
    cmp     ecx, eax
    jb      .endif
        add     esp, 4
        jmp     _index_out_of_bounds
.endif:
    carcdr  eax, S
    mov     word [edx + ecx*2], ax
    pop     eax
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; VREF - Get element of vector
;
; TRANSITION:  (v i.s) e (VREF.c) d  -->  (v[i].s) e c d
; ------------------------------------------------------------------------------
_instr_VREF:
    carcdr  eax, S
    carcdr  ecx, S
    ivalue  eax 
    ivalue  ecx
    mov     edx, eax
    call    _heap_item_length   ; Does not clobber ECX, EDX
    shr     eax, 1
    cmp     ecx, eax
    jb      .endif  
        jmp     _index_out_of_bounds
.endif:
    mov     eax, 0
    mov     ax, word [edx + ecx*2]
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; VLEN - Get length of vector
;
; TRANSITION:  (v.s) e (VLEN.c) d  -->  (n.s) e c d
;              where n is the number of elements in v
; ------------------------------------------------------------------------------
_instr_VLEN:
    carcdr  eax, S
    ivalue  eax
    call    _heap_item_length
    shr     eax, 1
    number  eax, eax
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; VCPY - Bulk copy between vectors
;
; TRANSITION:  (v i w j n.s) e (VCPY.c) d  -->  (v.s) e c d
; SIDE EFFECT:  w[j+k] <-- v[i+k] for all k, 0 ≤ k < n
; ------------------------------------------------------------------------------
_instr_VCPY:
    push    esi
    push    edi
    carcdr  eax, S
    carcdr  ecx, S
    ivalue  eax
    ivalue  ecx
    lea     esi, [eax + ecx*2]
    call    _heap_item_length
    shr     eax, 1
    sub     eax, ecx
    mov     edx, eax
    carcdr  eax, S
    carcdr  ecx, S
    push    eax
    ivalue  eax
    ivalue  ecx
    lea     edi, [eax + ecx*2]
    call    _heap_item_length
    shr     eax, 1
    sub     eax, ecx
    carcdr  ecx, S
    ivalue  ecx
    cmp     ecx, eax
    ja      .out_of_bounds
    cmp     ecx, edx
    ja      .out_of_bounds
    jmp     .loop
.out_of_bounds:
    pop     eax
    pop     edi
    pop     esi
    jmp     _index_out_of_bounds
    cld
.loop:
        jcxz    .endloop
        rep     movsw
        jmp     .loop
.endloop:
    pop     eax
    pop     edi
    pop     esi 
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; CBIN - Create binary blob
;
; TRANSITION:  (n.s) e (CBIN.c) d  -->  (b.s) e c d
;              where b is a newly allocated n-byte binary blob
; ------------------------------------------------------------------------------
_instr_CBIN:
    carcdr  eax, S      ; EAX <-- length of binary
    ivalue  eax
    call    _malloc
    alloc   eax, eax, SECD_BINARY
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; BSET - Set byte in binary blob
;
; TRANSITION:  (b i x.s) e (BSET.c) d  -->  (b.s) e c d
; SIDE EFFECT:  [b+i] <-- x
; ------------------------------------------------------------------------------
_instr_BSET:
    carcdr  eax, S
    carcdr  ecx, S
    push    eax
    ivalue  eax 
    ivalue  ecx
    mov     edx, eax
    call    _heap_item_length   ; Does not clobber ECX, EDX
    cmp     ecx, eax
    jb      .endif
        add     esp, 4
        jmp     _index_out_of_bounds
.endif:
    carcdr  eax, S
    ivalue  eax
    mov     byte [edx + ecx], al
    pop     eax
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; BGET - Get byte in binary blob
;
; TRANSITION:  (b i.s) e (BGET.c) d  -->  ([b+i].s) e c d
; ------------------------------------------------------------------------------
_instr_BREF:
    carcdr  eax, S
    carcdr  ecx, S
    ivalue  eax 
    ivalue  ecx
    mov     edx, eax
    call    _heap_item_length   ; Does not clobber ECX, EDX
    cmp     ecx, eax
    jb      .endif  
        jmp     _index_out_of_bounds
.endif:
    mov     eax, 0
    mov     al, byte [edx + ecx]
    number  eax, eax
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; BLEN - Get size of binary blob
;
; TRANSITION:  (b.s) e (BLEN.c) d  -->  (n.s) e c d
;              where n is the length of b, in bytes
; ------------------------------------------------------------------------------
_instr_BLEN:
    carcdr  eax, S
    ivalue  eax
    call    _heap_item_length
    number  eax, eax
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; BCPY - Bulk copy between binary blobs
;
; TRANSITION:  (b1 i b2 j n.s) e (BCPY.c) d  -->  (b1.s) e c d
; SIDE EFFECT:  b2[j+k] <-- b1[i+k] for all k, 0 ≤ k < n
; ------------------------------------------------------------------------------
_instr_BCPY:
    push    esi
    push    edi
    carcdr  eax, S
    carcdr  ecx, S
    ivalue  eax
    ivalue  ecx
    lea     esi, [eax + ecx]
    call    _heap_item_length
    sub     eax, ecx
    mov     edx, eax
    carcdr  eax, S
    carcdr  ecx, S
    push    eax
    ivalue  eax
    ivalue  ecx
    lea     edi, [eax + ecx]
    call    _heap_item_length
    sub     eax, ecx
    carcdr  ecx, S
    ivalue  ecx
    cmp     ecx, eax
    ja      .out_of_bounds
    cmp     ecx, edx
    ja      .out_of_bounds
    jmp     .loop
.out_of_bounds:
    pop     eax
    pop     edi
    pop     esi
    jmp     _index_out_of_bounds
    cld
.loop:
        jcxz    .endloop
        rep     movsb
        jmp     .loop
.endloop:
    pop     eax
    pop     edi
    pop     esi 
    xchg    S, eax
    cons    S, eax
    jmp     _cycle

; ------------------------------------------------------------------------------
; BS16 - Set 16-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i x.s) e (BSET.c) d  -->  (b.s) e c d
; SIDE EFFECT:  [b+i*2]@2 <-- x
; ------------------------------------------------------------------------------
_instr_BS16:
    jmp     _illegal

; ------------------------------------------------------------------------------
; BG16 - Get 16-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i.s) e (BGET.c) d  -->  ([b+i*2]@2.s) e c d
; ------------------------------------------------------------------------------
_instr_BR16:
    jmp     _illegal

; ------------------------------------------------------------------------------
; BS32 - Set 32-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i x.s) e (BSET.c) d  -->  (b.s) e c d
; SIDE EFFECT:  [b+i*4]@4 <-- x
; ------------------------------------------------------------------------------
_instr_BS32:
    jmp     _illegal

; ------------------------------------------------------------------------------
; BG32 - Get 32-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i.s) e (BGET.c) d  -->  ([b+i*4]@4.s) e c d
; ------------------------------------------------------------------------------
_instr_BR32:
    jmp     _illegal

_index_out_of_bounds:
    call    _flush
    sys.write stderr, err_oob, err_oob_len
    sys.exit 1
.halt:
    jmp     .halt
    

; ==============================================================================
; Garbage Collection
;
; We use a compacting garbage collector to find unreferenced cells.  We
; begin by marking the cells referenced by the registers of the machine: S, E,
; C, D, true, and false.  Whenever we mark a cons cell, we recursively mark that
; cell's car and cdr (if they are not already marked).  After this phase is
; complete, we iterate over all cells and relocate the marked (i.e. in use)
; cells to a contiguous block at the beginning of the cell array.
; 

; ------------------------------------------------------------------------------
; Traces referenced cells starting with the registers of the SECD machine
;
_trace:
    push    eax         ; Save current SECD-machine state
    push    ecx
    push    edx
    push    S
    push    C

    ; Clear all marks
    mov     ecx, 65536
    mov     edx, dword flags
.loop_clearmarks:
        and     [edx], byte ~SECD_MARKED
        inc     edx
        dec     ecx
        jnz     .loop_clearmarks

    ; Trace from root references (SECD-machine registers)
    mov     eax, S
    call    _mark
    mov     eax, C
    call    _mark
    mov     eax, [E]
    call    _mark
    mov     eax, [D]
    call    _mark
    mov     eax, [true]
    call    _mark
    mov     eax, [false]
    call    _mark
    mov     eax, 0
    call    _mark

; Sanity check -- scan free list for marked cells.  There should not be any.
%ifdef DEBUG
    mov     eax, ff
.loop_checkff:
        cmp     eax, 0xffff
        jg      .done                               ; while (eax <= 0xffff)
        test    byte [flags + eax], SECD_MARKED     ;   if cell marked...
        jnz     .error                              ;     break to error
        inc     eax                                 ;   advance to next cell
        jmp     .loop_checkff                       ; end while
.error:
    call    _flush                                  ; found in-use cell in free
    sys.write stderr, err_ff, err_ff_len            ; list.
    sys.exit 1
.halt:
    jmp     .halt

.done:
%endif  ; DEBUG

    pop     C           ; Restore SECD-machine state
    pop     S
    pop     edx
    pop     ecx
    pop     eax
    ret

; ------------------------------------------------------------------------------
; Find and mark referenced cells recursively
; EXPECTS eax = the index of the cell from which to start tracing
;
_mark:
    mov     dl, byte [flags + eax]          ; DL <-- flags for current cell
    test    dl, SECD_MARKED
    jz      .if
    ret                                     ; quit if cell already marked
    .if:
        or      dl, SECD_MARKED
        mov     byte [flags + eax], dl      ; mark this cell
        test    dl, SECD_ATOM
        jnz     .else                       ; if this is a cons cell then...
            cdrcar  edx, eax                ; recurse on car and cdr
            push    edx
            call    _mark
            pop     eax
            jmp     _mark
    .else:
        test    dl, SECD_HEAP               ; if cell is a heap reference...
        jz      .endif
        push    ebx
        mov     ebx, eax
        ivalue  eax
        test    byte [gcheap], HEAP_FORWARD
        jz      .endif_heap_forward
            call    _heap_forward           ; update reference if forwarded
            mov     [values + ebx * 4], eax         
    .endif_heap_forward:    
        test    byte [gcheap], HEAP_MARK
        jz      .endif_heap_mark            ; if heap item not marked then...
            call    _heap_mark              ; mark the heap item
    .endif_heap_mark:
        and     dl, SECD_TYPEMASK
        cmp     dl, SECD_VECTOR
        jne     .endif_vector               ; if cell is a vector reference...
            mov     eax, ebx
            call    _heap_item_length
            mov     ecx, eax
            shr     ecx, 1
        .loop:                              ; recurse on all entries in vector
                mov     eax, 0
                mov     ax, word [ebx]
                add     ebx, 2
                push    ecx
                call    _mark
                pop     ecx
                loop    .loop
    .endif_vector:
        pop     ebx 
.endif:
    ret


; ------------------------------------------------------------------------------
; Generic sort (quicksort)
; 
; Requires:
;   ESI - start index (inclusive) of range to sort
;   EDI - end index (inclusive) of range to sort
;   EBX - address of compare function
;   ECX - address of swap function
;
; Destroys: EAX, EDX, ESI

; Compare function must have the following characteristics:
;   Requires:
;     ESI - index of left side of comparison
;     EDI - index of right side of comparison
;   Ensures:
;     ZF  - indicates whether left side = right side
;     SF  - indicates whether left side < right side
;   Preserves: ESI, EDI, EBX, ECX
;   Destroys: EAX, EDX
;   
; Swap function must have the following characteristics:
;   Requires:
;     ESI - index of first element
;     EDI - index of second element
;   Preserves: ESI, EDI, EBX, ECX
;   Destroys: EAX, EDX
;

_test_sort:
    mov     [values + 0 * 4], dword 3
    mov     [values + 1 * 4], dword 7
    mov     [values + 2 * 4], dword 8
    mov     [values + 3 * 4], dword 5
    mov     [values + 4 * 4], dword 2
    mov     [values + 5 * 4], dword 1
    mov     [values + 6 * 4], dword 9
    mov     [values + 7 * 4], dword 5
    mov     [values + 8 * 4], dword 4
    mov     esi, 0
    mov     edi, 9
    mov     ebx, .test_compare
    mov     ecx, .test_swap
    call    _sort
.done_test_sort:
    ret
.test_compare:
    mov     eax, [values + esi * 4]
    mov     edx, [values + edi * 4]
    cmp     eax, edx
    ret
.test_swap:
    mov     eax, [values + esi * 4]
    mov     edx, [values + edi * 4]
    mov     [values + esi * 4], edx
    mov     [values + edi * 4], eax
    ret

_sort:
    push    esi
    call    .sort
    pop     esi
    ret

.sort:
    ; Make sure we have something to sort
    cmp     esi, edi
    mov     eax, edi
    sub     eax, esi
    cmp     eax, 1
    jg      .continue
        ret
.continue:

    push    edi
    push    esi

    ; EAX = (ESI + EDI) / 2
    mov     eax, edi
    sub     eax, esi
    shr     eax, 1
    add     eax, esi

    dec     esi

.loop_pivot:

        xchg    eax, edi
    .loop_scan_a:
            cmp     esi, edi
            jge     .done_loop_scan_a
            inc     esi
            pusha
            call    ebx   ; TODO: Preserve destroyed registers
            popa
            jle     .loop_scan_a
    .done_loop_scan_a:
    
        xchg    eax, esi
    .loop_scan_b:
            cmp     esi, edi
            jle     .done_loop_scan_b
            dec     esi
            pusha
            call    ebx   ; TODO: Preserve destroyed registers
            popa
            jge     .loop_scan_b
    .done_loop_scan_b:

        xchg    eax, edi
        xchg    esi, edi
        cmp     esi, edi
        jae     .done_pivot

            cmp     eax, esi
            cmove   eax, edi
            je      .endif
                cmp     eax, edi
                cmove   eax, esi
        .endif:

            pusha
            call    ecx   ; TODO: Preserve destroyed registers
            popa
            jmp     .loop_pivot

.done_pivot:
;    pop     esi
    xchg    esi, [esp]
;    inc     edi
    call    .sort

    pop     esi
    pop     edi
    jmp     .sort   ; tail recursion


_compare_atom:
    mov     edx, [values2 + esi * 4]
    and     edx, 0xffff
    mov     al, [flags + edx]

    mov     edx, [values2 + edi * 4]
    and     edx, 0xffff
    mov     ah, [flags + edx]

    mov     dx, ax
    and     al, SECD_ATOM
    and     ah, SECD_ATOM

    ; If one is an atom and the other isn't, the atom is lesser
    cmp     ah, al
    jne     .done     

    ; If both are cons cells, we consider them equal
    cmp     al, 0
    je      .done

    ; If both are atoms, next compare their types
    and     dl, SECD_TYPEMASK
    and     dh, SECD_TYPEMASK
    cmp     dh, dl
    jne     .done

    ; If both are the same type, compare their values
    mov     eax, [values2 + esi * 4]
    and     eax, 0xffff
    mov     eax, [values + eax * 4]

    mov     edx, [values2 + edi * 4]
    and     edx, 0xffff
    mov     edx, [values + edx * 4]

    cmp     eax, edx
    jne     .done

    ; If both have the same value, compare their original locations.  This
    ; ensures that the first occurrance of a given atom is the one that is
    ; kept.  This is important because the NIL symbol must occupy cell zero.
    mov     eax, [values2 + esi * 4]
    and     eax, 0xffff
    mov     edx, [values2 + edi * 4]
    and     edx, 0xffff
    cmp     eax, edx

.done:
    ret

_compare_cons:
    push    ebx
    push    ecx

    sub     esp, 4

    mov     ebx, [mark]
    mov     ecx, 0

    mov     eax, [values2 + esi * 4]
    and     eax, 0xffff
    mov     eax, [values + eax * 4]
    mov     edx, eax
    shr     edx, 16
    and     eax, 0xffff
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    cmp     eax, ebx
    jae     .done_check_a
    mov     edx, [values2 + edx * 4]
    shr     edx, 16
    cmp     edx, ebx
    jae     .done_check_a
        mov     cl, 1
        shl     edx, 16
        or      eax, edx
        mov     [esp], eax
.done_check_a:

    mov     eax, [values2 + edi * 4]
    and     eax, 0xffff
    mov     eax, [values + eax * 4]
    mov     edx, eax
    shr     edx, 16
    and     eax, 0xffff
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    cmp     eax, ebx
    jae     .done_check_b
    mov     edx, [values2 + edx * 4]
    shr     edx, 16
    cmp     edx, ebx
    jae     .done_check_b
        mov     ch, 1
        shl     edx, 16
        or      eax, edx
.done_check_b:

    cmp     ch, cl
    jne     .done

    cmp     cl, 0
    je      .done

    mov     edx, [esp]
    cmp     eax, edx

.done:
    pop     eax   ; Can't do "add esp, 4" because that would affect the flags
    pop     ecx
    pop     ebx
    ret
    


    
; ------------------------------------------------------------------------------
; Collapse duplicate cells
; ========================
; 
; Allocated cells in the SECD machine are immutable.  Therefore, it is valid
; to restructure the cell graph so that:
;
;   - no two cells contain the same atomic value, and furthermore that
;   - whenever two cons cells, say A and B, are such that the subgraph reachable
;     from A is identical to the subgraph reachable from B (in structure and in
;     the atomic values reachable from A or B), that A and B are in fact the
;     same cell.
;
; This can lead to a significant reduction in cell usage, as a typical running
; SECD machine will have many cells containing common values (e.g., small
; numbers, common symbols, common code fragments, etc.).
;
; This algorithm is much more expensive than the basic garbage collection, so we
; only do this as a last resort when the basic garbage collection fails to yield
; sufficient space.
;
;
; Working Array
; -------------
;
; To accomplish this task, we must be able to rearrange cells in a potentially
; very full cell array.  We will need a second working area for this task.  In
; this working area, we store the permutation that transforms the original
; arrangement of the cells into the new arrangement.  Each DWORD value in the
; working array contains:
;
;   [31.....FWD....16|15.....REF.....0]
;
;     FWD = The index into the cell array of the location where the cell that
;           was originally here has moved.
;     REF = The index into the original cell array of the cell that should be
;           moved to this location.
;
; We sort, swap, and collapse cells by rearranging cells in this working array,
; and only at the end do we update the actual cell array.
;
;
; Algorithm
; ---------
;
; We determine if two cells contain identical values simply by looking at the
; type and value stored in the cell array.  For atomic values, this is
; sufficient.  However, two cons cells may be identical but not share the same
; numerical values if their CARs and CDRs have not been collapsed.
;
; Example:
; 
;   Index:   0     1   2   3              4
;   Value: [ NIL | A | A | CAR=1, CDR=0 | CAR=2, CDR=0 ]
;
;   In this example, cells 3 and 4 are identical, but because cells 1 and 2
;   have not yet been collapsed to a single cell, a comparison of the numerical
;   values stored in 3 and 4 is insufficient to detect that they are identical.
;
; We therefore collapse the cell array in phases:
;
;   - Phase 0: Find and collapse the atoms.
;   - Phase 1: Find and collapse the 'Level 1' cons cells (those whose CAR and
;              CDR are both atoms).
;   - Phase 2: Find the collapse the 'Level 2' cons cells (those whose CAR and
;              CDR are both atomic or 'Level 1' cons).
;   ...
;   - Phase N: Find and collapse the 'Level N' cons cells (those whose CAR and
;              CDR are both atomic or 'Level K' cons with K < N).
;
; Each phase proceeds by:
;
;   - Partitioning the remaining cells (those on the right side of a 'mark'
;     value, those cells to the left 'mark' have already been collapsed) so that
;     atomic (Phase 0) or 'Level N' (Phase N, N > 0) cells are on the left,
;     sorted by their numerical value, and all other cells (Level K cells,
;     K > N) are on the right.
;   - Collapse the cells in the partition on the left.
;   - Update the 'mark' to point at the start of the partition on the right.
;
; Each phase must result in no more collapsed cells than the prior phase, since
; we cannot have a common 'Level N' graph without also having a common
; 'Level N-1' graph.  Therefore, if a phase fails to find any cons cells to be
; collapsed, the algorithm terminates.  The algorithm also terminates if the
; 'mark' reaches the end of the cell array.
;
;
; Requires:
; EDI - number of occupied cells
;
_test_dedup:

    ; Load an image of the S-expression "( ( 3 2 1 . 0 ) ( 4 2 1 . 0 ) 1 2 . 0 )

    mov     [Sreg], dword 3
    mov     [E], dword 3
    mov     [Creg], dword 3
    mov     [D], dword 3

    mov     [values +  0 * 4], dword 0x000a0009
    mov     [values +  1 * 4], dword 2
    mov     [values +  2 * 4], dword 0x00010010
    mov     [values +  3 * 4], dword 0x00000005 ; <--- Root
    mov     [values +  4 * 4], dword 0x00140002
    mov     [values +  5 * 4], dword 0x0004000b
    mov     [values +  6 * 4], dword 0x00130012
    mov     [values +  7 * 4], dword 0x0011000d
    mov     [values +  8 * 4], dword 2
    mov     [values +  9 * 4], dword 0x00080007
    mov     [values + 10 * 4], dword 3
    mov     [values + 11 * 4], dword 0x000c0006
    mov     [values + 12 * 4], dword 1
    mov     [values + 13 * 4], dword 0
    mov     [values + 14 * 4], dword 0
    mov     [values + 15 * 4], dword 1
    mov     [values + 16 * 4], dword 0x000f000e
    mov     [values + 17 * 4], dword 1
    mov     [values + 18 * 4], dword 0
    mov     [values + 19 * 4], dword 2
    mov     [values + 20 * 4], dword 4

    mov     al, SECD_NUMBER | SECD_ATOM | SECD_MARKED
    mov     ah, SECD_MARKED
    mov     [flags +  0], ah
    mov     [flags +  1], al
    mov     [flags +  2], ah
    mov     [flags +  3], ah
    mov     [flags +  4], ah
    mov     [flags +  5], ah
    mov     [flags +  6], ah
    mov     [flags +  7], ah
    mov     [flags +  8], al
    mov     [flags +  9], ah
    mov     [flags + 10], al
    mov     [flags + 11], ah
    mov     [flags + 12], al
    mov     [flags + 13], al
    mov     [flags + 14], al
    mov     [flags + 15], al
    mov     [flags + 16], ah
    mov     [flags + 17], al
    mov     [flags + 18], al
    mov     [flags + 19], al
    mov     [flags + 20], al

    push    dword 3
    call    _putexp
    add     esp, 4
    call    _flush

    mov     edi, 21
    call    _dedup

    push    dword 3
    call    _putexp
    add     esp, 4
    call    _flush

    ret

_dedup:

    mov     [Sreg], S
    mov     [Creg], C

    ; Initialize sort map
    mov     esi, edi
    mov     eax, edi
    shl     eax, 16
    or      eax, edi
.loop_init:
        mov     [values2 + esi * 4], eax
        sub     eax, 0x00010001
        dec     esi
        jns     .loop_init

    mov     esi, 0
    mov     ebx, _compare_atom
    mov     ecx, .swap
    call    _sort

    ; Scan for first cons cell, collapsing equivalent atoms as we go
.loop_find_cons:
        mov     ecx, [values2 + esi * 4]
        and     ecx, 0xffff
        mov     al, [flags + ecx]
        test    al, SECD_ATOM
        jz      .done_loop_find_cons

        mov     eax, [values + ecx * 4]

        cmp     esi, 0
        je      .else_not_collapse

        cmp     eax, edx
        jne     .else_not_collapse
            mov     eax, [values2 + ecx * 4]
            and     eax, 0xffff
            or      eax, ebx
            mov     [values2 + ecx * 4], eax
            jmp     .endif_collapse
    .else_not_collapse:
            mov     ebx, esi
            shl     ebx, 16
            mov     edx, eax
    .endif_collapse:

        inc     esi
        jmp     .loop_find_cons
.done_loop_find_cons:

        sub     esp, 4
        push    edi

.loop_phase:
        mov     ebx, _compare_cons
        mov     ecx, .swap
        mov     [mark], esi
        mov     edi, [esp]
        call    _sort

        ; Scan for next level cons cell, collapsing equivalent cons cells as we
        ; go
        mov     [esp + 4], dword 0
        mov     ecx, esi
        shl     ecx, 16
        dec     esi
    .loop_mark:
            inc     esi
            mov     eax, [values2 + esi * 4]
            and     eax, 0xffff
            mov     al, [flags + eax]
            test    al, SECD_ATOM
            jnz     _memerror
            cmp     esi, [esp]
            jae     .done_loop_phase
            mov     edi, [values2 + esi * 4]
            and     edi, 0xffff
            mov     eax, [values + edi * 4]
            mov     edx, eax
            shr     edx, 16
            and     eax, 0xffff
            mov     eax, [values2 + eax * 4]
            shr     eax, 16
            mov     edx, [values2 + edx * 4]
            shr     edx, 16
            cmp     eax, [mark]
            jae     .endloop_phase
            cmp     edx, [mark]
            jae     .endloop_phase

            shl     edx, 16
            or      eax, edx

            cmp     esi, [mark]
            je      .else_not_collapse_cons
           
            cmp     eax, ebx
            jne     .else_not_collapse_cons

                mov     [esp + 4], dword 1

                mov     eax, [values2 + edi * 4]
                and     eax, 0xffff
                or      eax, ecx
                mov     [values2 + edi * 4], eax

                jmp     .loop_mark

        .else_not_collapse_cons:
                mov     ebx, eax
                mov     ecx, esi
                shl     ecx, 16

                mov     edx, eax
                shr     edx, 16
                and     eax, 0xffff
                mov     eax, [values2 + eax * 4]
                and     eax, 0xffff
                mov     edx, [values2 + edx * 4]
                shl     edx, 16
                or      eax, edx
                mov     [values + edi * 4], eax
                jmp     .loop_mark

    .endloop_phase:

            test    [esp + 4], dword 1
            jnz     .loop_phase

.done_loop_phase:
    pop     edi
    add     esp, 4

    ; Update SECD-machine registers
    mov     eax, [Sreg]
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    mov     eax, [values2 + eax * 4]
    and     eax, 0xffff
    mov     [Sreg], eax

    mov     eax, [E]
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    mov     eax, [values2 + eax * 4]
    and     eax, 0xffff
    mov     [E], eax

    mov     eax, [Creg]
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    mov     eax, [values2 + eax * 4]
    and     eax, 0xffff
    mov     [Creg], eax

    mov     eax, [D]
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    mov     eax, [values2 + eax * 4]
    and     eax, 0xffff
    mov     [D], eax

    mov     eax, [true]
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    mov     eax, [values2 + eax * 4]
    and     eax, 0xffff
    mov     [true], eax

    mov     eax, [false]
    mov     eax, [values2 + eax * 4]
    shr     eax, 16
    mov     eax, [values2 + eax * 4]
    and     eax, 0xffff
    mov     [false], eax

    mov     S, [Sreg]
    mov     C, [Creg]

    ret
        

.swap:

    ; Update forwarding pointers
    mov     edx, [values2 + esi * 4]
    and     edx, 0xffff
    mov     eax, [values2 + edx * 4]
    and     eax, 0xffff
    shl     eax, 16
    or      eax, edi
    ror     eax, 16
    mov     [values2 + edx * 4], eax

    mov     edx, [values2 + edi * 4]
    and     edx, 0xffff
    mov     eax, [values2 + edx * 4]
    and     eax, 0xffff
    shl     eax, 16
    or      eax, esi
    ror     eax, 16
    mov     [values2 + edx * 4], eax

    ; Exchange reference pointers
    mov     eax, [values2 + esi * 4]
    mov     edx, [values2 + edi * 4]
    xchg    ax, dx
    mov     [values2 + esi * 4], eax
    mov     [values2 + edi * 4], edx

    ret

    
    


; ------------------------------------------------------------------------------
; Relocates used cells to form a contiguous block
;
; Algorithm:
;   left = -1
;   right = NUM_CELLS
;
;   repeat {
;     increment left until cell[left] is free
;     decrement right until cell[right] is used
;     if (right <= left) break;
;
;     // relocate the cell and leave a breadcrumb to find it later
;     cell[left] <-- cell[right]
;     cell[right] <-- left    // relocation pointer
;   }
;
;   // at this point, 'right' points to the last used cell, and 'left' points
;   // to the first free cell
;   while (right >= 0) {      // loop through all the used cells
;
;     // follow breadcrumbs to fix cons cells whose car or cdr has been
;     // relocated
;     if cell[right] is a cons cell {
;       update car(cell[right]) if car(cell[left]) >= left
;       update cdr(cell[right]) if cdr(cell[left]) >= left
;     }
;
;     decrement right
;   }
;   
_compact:
    mov     [Sreg], S
    mov     [Creg], C

    push    eax         ; Save current SECD-machine state
    push    ecx
    push    edx

    mov     edi, -1                             ; left
    mov     esi, 0x10000                        ; right
.loop_find_free:
        inc     edi
        test    byte [flags + edi], SECD_MARKED ; is cell[left] free?
        jnz     .loop_find_free
.loop_find_used:
        dec     esi
        test    byte [flags + esi], SECD_MARKED ; is cell[right] used?
        jz      .loop_find_used
    cmp     esi, edi                            ; right <= left?
    jle     .loop_rewrite
        mov     eax, dword [values + esi * 4]   ; value[left] <-- value[right]
        mov     dword [values + edi * 4], eax
        mov     dword [values + esi * 4], edi   ; value[right] <-- left
        mov     al, byte [flags + esi]          ; flags[left] <-- flags[right]
        mov     byte [flags + edi], al
        mov     byte [flags + esi], 0           ; mark right cell as free
        jmp     .loop_find_free
.loop_rewrite:
        test    byte [flags + esi], SECD_ATOM   ; if cell[right] a cons cell:
        jnz     .endif_cons
            mov     eax, dword [values + esi * 4]
            mov     edx, eax                    ; split cell into car/cdr
            shr     eax, 16
            and     edx, 0xffff

            cmp     eax, edi                    ; if car >= left:
            jb      .endif_relocate_car
                mov     eax, dword [values + eax * 4] ; follow breadcrumb
        .endif_relocate_car:
            cmp     edx, edi                    ; if cdr >= left:
            jb      .endif_relocate_cdr
                mov     edx, dword [values + edx * 4] ; follow breadcrumb
        .endif_relocate_cdr:

            shl     eax, 16                     ; update cell
            or      eax, edx
            mov     dword [values + esi * 4], eax
            
    .endif_cons:
        dec     esi
        jns     .loop_rewrite

    ; Follow breadcrumbs for SECD-machine registers
    mov     eax, dword [Sreg]
    cmp     eax, edi
    jb      .endif_relocate_s
        mov     eax, dword [values + eax * 4]
        mov     dword [Sreg], eax
.endif_relocate_s:
    mov     eax, dword [E]
    cmp     eax, edi
    jb      .endif_relocate_e
        mov     eax, dword [values + eax * 4]
        mov     dword [E], eax
.endif_relocate_e:
    mov     eax, dword [Creg]
    cmp     eax, edi
    jb      .endif_relocate_c
        mov     eax, dword [values + eax * 4]
        mov     dword [Creg], eax
.endif_relocate_c:
    mov     eax, dword [D]
    cmp     eax, edi
    jb      .endif_relocate_d
        mov     eax, dword [values + eax * 4]
        mov     dword [D], eax
.endif_relocate_d:

    ; Restore state
    pop     edx
    pop     ecx
    pop     eax

    mov     S, [Sreg]
    mov     C, [Creg]

%ifnidni ff,edi
    mov     ff, edi     ; ff <-- start of free cells
%endif
    ret
        

; ------------------------------------------------------------------------------
; Finds unused cells and adds them to the free list.
;
_gc:
    call    _trace
    call    _compact

    cmp     ff, 0x10000 - DEDUP_THRESHOLD
    jle     .endif_dedup

%ifnidni ff,edi
        mov     edi, ff
%endif

        call    _dedup
        call    _trace
        call    _compact
.endif_dedup:

    ret

; ------------------------------------------------------------------------------
; Garbage collection for heap (vectors and binary blobs)              UNFINISHED
;
_heap_gc:
    mov     byte [gcheap], HEAP_MARK
    call    _trace
    call    _heap_sweep
    mov     byte [gcheap], HEAP_FORWARD
    call    _gc
    mov     byte [gcheap], 0
    ret

; ------------------------------------------------------------------------------
; Allocate a block of memory on the heap                              UNFINISHED
;
_malloc:
    push    eax
    call    _heap_alloc
    cmp     eax, 0
    jnz     .done
    call    _heap_gc
    mov     eax, [esp]
    call    _heap_alloc
    cmp     eax, 0
    jnz     .done
    call    _flush
    sys.write stderr, err_hf, err_hf_len
    sys.exit 1
.halt:
    jmp     .halt   
.done:
    add     esp, 4
    ret

