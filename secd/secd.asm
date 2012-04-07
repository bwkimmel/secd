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
; Flags
;
%define SECD_MARKED		0x80	; GC-bit for cell array
%define HEAP_MARK		0x01	; GC-bit for heap items
%define HEAP_FORWARD	0x02	; Indicates that heap item has been moved


; ==============================================================================
; Reserved registers
;
%define S ebx		; (S)tack
%define C esi		; (C)ontrol
%define ff edi		; Head of the free list (ff)


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
	jmp		.halt

; ------------------------------------------------------------------------------
; Checks that the specified value is a valid cell reference.
; ------------------------------------------------------------------------------
_check_cell_ref:
	enter	0, 0
	cmp		dword [ebp + 8], 0xffff
	ja		_bad_cell_ref
	leave
	ret

%macro check_cell_ref 1
	push	dword %1
	call	_check_cell_ref
	add		esp, 4
%endmacro

%else	; !DEBUG

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
	push	S
	push	C
	push	ff
%endmacro

; ------------------------------------------------------------------------------
; Restore reserved registers after an external function call
; USAGE: popsecd
; ------------------------------------------------------------------------------
%macro popsecd 0
	pop		ff
	pop		C
	pop		S
%endmacro

; ------------------------------------------------------------------------------
; Extracts the first element of a cons cell
; USAGE: car <dest>, <src>
; <dest> = the location to put the result into
; <src>  = the cons cell from which to exract the first element
; ------------------------------------------------------------------------------
%macro car 2 
	check_cell_ref %2
	mov		%1, [dword values + %2 * 4]
	shr		%1, 16
%endmacro

; ------------------------------------------------------------------------------
; Extracts the second element of a cons cell
; USAGE: cdr <dest>, <src>
; <dest> = the location to put the result into
; <src>  = the cons cell from which to extract the second element
; ------------------------------------------------------------------------------
%macro cdr 2
	check_cell_ref %2
	mov		%1, [dword values + %2 * 4]
	and		%1, 0xffff
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
	mov		%2, [dword values + %2 * 4]
	mov		%1, %2
	shr		%1, 16
	and		%2, 0xffff
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
	mov		%2, [dword values + %2 * 4]
	mov		%1, %2
	and		%1, 0xffff
	shr		%2, 16
%endmacro

; ------------------------------------------------------------------------------
; Dereferences a cell index
; USAGE: ivalue <dest>
; <dest> = the index into the cell array to dereference, and the location into
;          which to put the value at that location
; ------------------------------------------------------------------------------
%macro ivalue 1
	check_cell_ref %1
	mov		%1, [dword values + %1 * 4]
%endmacro

; ------------------------------------------------------------------------------
; Allocates a cell for a new value
; USAGE: alloc <dest>, <value>, <flags>
; <dest>  = the location in which to put the index of the newly allocated cell
; <value> = the value to place in the new cell
; <flags> = the flags indicating the type of the new cell
; ------------------------------------------------------------------------------
%macro alloc 3
	cmp		ff, 0						; check if we have free cells available
	jne		%%nogc
	jmp		_gc.out_of_space
	call	_gc
%%nogc:
	dec		dword [free]
	mov		byte [flags + ff], %3		; set flags for new cell
%ifidni %1,%2							; special handling if <dest> == <value>
	xchg	%1, ff
	xchg	ff, [dword values + %1 * 4]
	and		ff, 0xffff
%else									; <dest> != <value>
	mov		%1, ff
	cdr		ff, ff
	mov		[dword values + %1 * 4], %2
%endif
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
	shl		%1, 16
	or		%1, %2
	alloc	%1, %1, SECD_CONS
%endmacro

; ------------------------------------------------------------------------------
; Allocates a new number cell
; USAGE: number <dest>, <value>
; <dest>  = the location in which to put the index of the new cell
; <value> = the numeric value to place in the new cell
; ------------------------------------------------------------------------------
%macro number 2
	alloc	%1, %2, SECD_NUMBER
%endmacro

; ------------------------------------------------------------------------------
; Allocates a new symbolic cell
; USAGE: symbol <dest>, <value>
; <dest>  = the location in which to put the index of the new cell
; <value> = the address of the symbol in the string store
; ------------------------------------------------------------------------------
%macro symbol 2
	alloc	%1, %2, SECD_SYMBOL
%endmacro

; ------------------------------------------------------------------------------
; Tests if the indicate cell is a number cell.  If it is, ZF will be clear,
; otherwise ZF will be set.
; USAGE: isnumber <cell>
; <cell> = the cell to test
; ------------------------------------------------------------------------------
%macro isnumber 1
	check_cell_ref %1
	test	byte [flags + %1], 0x02
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
	jz		_arith_nonnum
	isnumber %2
	jz		_arith_nonnum
%endmacro


; ==============================================================================
; Builtin strings
;
segment .data
tstr		db		"T"
tstr_len	equ		$ - tstr
fstr		db		"F"
fstr_len	equ		$ - fstr
nilstr		db		"NIL"
nilstr_len	equ		$ - nilstr
err_ii		db		"Illegal instruction", 10
err_ii_len	equ		$ - err_ii
err_mem		db		"Memory error", 10
err_mem_len	equ		$ - err_mem
err_hf		db		"Out of heap space", 10
err_hf_len	equ		$ - err_hf
err_car		db		"Attempt to CAR an atom", 10
err_car_len	equ		$ - err_car
err_cdr		db		"Attempt to CDR an atom", 10
err_cdr_len	equ		$ - err_cdr
err_oob		db		"Index out of bounds", 10
err_oob_len	equ		$ - err_oob

%ifdef DEBUG
err_ff		db		"Free cells in use", 10
err_ff_len	equ		$ - err_ff
err_bc		db		"Bad cell reference", 10
err_bc_len	equ		$ - err_bc
%endif

sep			db		10, "-----------------", 10
sep_len		equ		$ - sep
maj_sep		db		10, "==============================================", 10
maj_sep_len	equ		$ - maj_sep
free		dd		0
gcheap		db		0


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
values		resd	65536	; Storage for cons cells and ivalues
flags		resb	65536	; Storage for isatom and isnumber bits


; ==============================================================================
; SECD-machine registers stored in memory
;
E			resd	1		; (E)nvironment register
D			resd	1		; (D)ump register
true		resd	1		; true register
false		resd	1		; false register
Sreg		resd	1
Creg		resd	1
ffreg		resd	1


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

; ------------------------------------------------------------------------------
; Prints the current state of the machine for diagnostic purposes
;
_dumpstate:
	sys.write stdout, maj_sep, maj_sep_len
	push	dword S
	call	_putexp
	add		esp, 4
	call	_flush
	sys.write stdout, sep, sep_len

	push	dword [E]
	call	_putexp
	add		esp, 4
	call	_flush
	sys.write stdout, sep, sep_len
	
	push	C
	call	_putexp
	add		esp, 4
	call	_flush
	ret

_car:
	car		eax, eax
	ret

_cdr:
	cdr		eax, eax
	ret

_ivalue:
	ivalue	eax
	ret

_svalue:
	ivalue	eax
	ret

_cons:
	xchg	ff, [ffreg]
	cons	eax, edx
	xchg	ff, [ffreg]
	ret

_number:
	xchg	ff, [ffreg]
	number	eax, eax
	xchg	ff, [ffreg]
	ret

_symbol:
	xchg	ff, [ffreg]
	symbol	eax, eax
	xchg	ff, [ffreg]
	ret

_flags:
	mov		al, byte [flags + eax]
	and		eax, 0x000000ff
	ret

_issymbol:
	call	_flags
	and		eax, SECD_TYPEMASK
	cmp		eax, SECD_SYMBOL
	sete	al	
	ret

_isnumber:
	call	_flags
	and		eax, SECD_TYPEMASK
	cmp		eax, SECD_NUMBER
	sete	al
	ret

_iscons:
	call	_flags
	and		eax, SECD_TYPEMASK
	cmp		eax, SECD_CONS
	sete	al
	ret

_init:
	enter	0, 0
	; Initialize free list
	mov		eax, 1
	lea		edi, [dword values + 4]
	mov		ecx, 65535
	cld
.init:
		inc		eax
		stosd
		loop	.init
	mov		[edi], dword 0
	mov		ff, 1
	push	dword tstr_len
	push	dword tstr
	call	_store
	add		esp, 8
	symbol	eax, eax
	mov		[true], eax
	push	dword fstr_len
	push	dword fstr
	call	_store
	add		esp, 8
	symbol	eax, eax
	mov		[false], eax
	push	dword nilstr_len
	push	dword nilstr
	call	_store
	add		esp, 8
    mov		byte [flags], SECD_SYMBOL
	mov		dword [values], eax
	mov		[ffreg], ff
	leave
	ret

_exec:
	enter	0, 0
	push	ebx
	push	esi
	push	edi
	mov		ff, [ffreg]
	mov		C, [ebp + 8]	; C <-- fn
	and		C, 0xffff
	mov		S, [ebp + 12]	; S <-- args
	and		S, 0xffff
	mov		[E], dword 0
	mov		[D], dword 0
	cons	S, 0
	mov		eax, dword free
	mov		[eax], dword 0
	;
	; ---> to top of instruction cycle ...
	

; ==============================================================================
; Top of SECD Instruction Cycle
;
_cycle:
	mov		eax, dword free				; call GC if we have < 10 free cells
	cmp		[eax], dword 10
	jg		.nogc
	cmp		[eax], dword 0
	jl		_memerror
	push	eax
	call	_gc
	pop		eax
.nogc:
	check_cell_ref dword S				; Check that all registers are valid
	check_cell_ref dword [E]			; cell references
	check_cell_ref dword C
	check_cell_ref dword [D]
	check_cell_ref dword ff
	carcdr	eax, C						; Pop next instruction from code list
	ivalue	eax							; Get its numeric value
	cmp		eax, dword numinstr			; Check that it is a valid opcode
	jae		_illegal
	jmp		[dword _instr + eax * 4]	; Jump to opcode handler

_illegal:
	call	_flush
	sys.write stderr, err_ii, err_ii_len
	sys.exit 1
.stop:
	jmp		.stop
	
_memerror:
	call	_flush
	sys.write stderr, err_mem, err_mem_len
	sys.exit 1
.stop:
	jmp		.stop


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
	dd	_instr_NOP , \
		_instr_LD  , _instr_LDC , _instr_LDF , _instr_AP  , _instr_RTN , \
		_instr_DUM , _instr_RAP , _instr_SEL , _instr_JOIN, _instr_CAR , \
		_instr_CDR , _instr_ATOM, _instr_CONS, _instr_EQ  , _instr_ADD , \
		_instr_SUB , _instr_MUL , _instr_DIV , _instr_REM , _instr_LEQ , \
		_instr_STOP, _instr_SYM , _instr_NUM , _instr_GET , _instr_PUT , \
		_instr_APR , _instr_TSEL, _instr_MULX, _instr_PEXP, _instr_POP, \
		_instr_CVEC, _instr_VSET, _instr_VREF, _instr_VLEN, _instr_VCPY, \
		_instr_CBIN, _instr_BSET, _instr_BREF, _instr_BLEN, _instr_BCPY, \
		_instr_BS16, _instr_BR16, _instr_BS32, _instr_BR32

numinstr	equ		($ - _instr) >> 2
	

; ==============================================================================
; SECD Instruction Implementations
;

; ------------------------------------------------------------------------------
; NOP - No operation
;
; TRANSITION:  s e (NOP.c) d  -->  s e c d
; ------------------------------------------------------------------------------
_instr_NOP:
	jmp		_cycle

; ------------------------------------------------------------------------------
; POP - Pop item off of the stack
;
; TRANSITION:  (x.s) e (POP.c) d  -->  s e c d
; ------------------------------------------------------------------------------
_instr_POP:
	cdr		S, S
	jmp		_cycle

; ------------------------------------------------------------------------------
; LD - Load (from environment)
;
; TRANSITION:  s e (LD i.c) d  -->  (x.s) e c d
;              where x = locate(i,e)
; ------------------------------------------------------------------------------
_instr_LD:
	mov		eax, [E]	; W <-- E
	carcdr	edx, C		; EDX <-- car(cdr(C)), C' <-- cdr(cdr(C))

	carcdr	ecx, edx	; ECX <-- car(car(cdr(C))), EDX <-- cdr(car(cdr(C)))
	ivalue	ecx
	jcxz	.endloop1
.loop1:					; FOR i = 1 TO car(car(cdr(C)))
		cdr		eax, eax	; W <-- cdr(W)
		loop	.loop1
.endloop1:

	car		eax, eax	; W <-- car(W)
	mov		ecx, edx	; ECX <-- cdr(car(cdr(C)))
	ivalue	ecx
	jcxz	.endloop2
.loop2:					; FOR i = 1 TO cdr(car(cdr(C)))
		cdr		eax, eax	; W <-- cdr(W)
		loop	.loop2
.endloop2:

	car		eax, eax	; W <-- car(W)
	cons	eax, S
	mov		S, eax		; S <-- cons(W, S)
	jmp		_cycle
	
; ------------------------------------------------------------------------------
; LDC - Load constant
;
; TRANSITION:  s e (LDC x.c) d  --> (x.s) e c d
; ------------------------------------------------------------------------------
_instr_LDC:
	carcdr	eax, C
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; LDF - Load function
;
; TRANSITION:  s e (LDF c'.c) d  --> ((c'.e).s) e c d 
; ------------------------------------------------------------------------------
_instr_LDF:
	carcdr	eax, C
	cons	eax, [E]
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; AP - Apply function
;
; TRANSITION:  ((c'.e') v.s) e (AP.c) d  -->  NIL (v.e') c' (s e c.d)
; ------------------------------------------------------------------------------
_instr_AP:
	cons	C, [D]
	mov		eax, [E]
	cons	eax, C		; EAX <-- cons(E, cons(cdr(C), D))
	carcdr	edx, S		; EDX <-- car(S), S' <-- cdr(S)
	carcdr	C, edx		; C' <-- car(car(S)), EDX <-- cdr(car(S))
	carcdr	ecx, S		; ECX <-- car(cdr(S)), S' <-- cdr(cdr(S))
	cons	S, eax
	mov		[D], S		; D' <-- cons(cdr(cdr(S)), cons(e, cons(cdr(c), d)))
	cons	ecx, edx
	mov		[E], ecx	; E' <-- cons(car(cdr(S)), cdr(car(S)))
	mov		S, 0		; S' <-- nil
	jmp		_cycle

; ------------------------------------------------------------------------------
; RTN - Return
;
; TRANSITION:  (x) e' (RTN) (s e c.d)  -->  (x.s) e c d
; ------------------------------------------------------------------------------
_instr_RTN:
	mov		edx, [D]
	carcdr	eax, edx	; EAX <-- car(D), EDX <-- cdr(D)
	car		S, S
	cons	S, eax		; S' <-- cons(car(S), car(D))
	carcdr	eax, edx	; EAX <-- car(cdr(D)), EDX <-- cdr(cdr(D))
	mov		[E], eax	; E' <-- car(cdr(D))
	carcdr	C, edx		; C' <-- car(cdr(cdr(D))), EDX <-- cdr(cdr(cdr(D)))
	mov		[D], edx	; D' <-- cdr(cdr(cdr(D)))
	jmp		_cycle
	
; ------------------------------------------------------------------------------
; DUM - Create dummy environment
;
; TRANSITION:  s e (DUM.c) d  -->  s (Ω.e) c d
; ------------------------------------------------------------------------------
_instr_DUM:
	mov		eax, 0
	cons	eax, [E]
	mov		[E], eax	; E' <-- cons(nil, E)
	jmp		_cycle
	
; ------------------------------------------------------------------------------
; RAP - Recursive apply
;
; TRANSITION:  ((c'.e') v.s) (Ω.e) (RAP.c) d  -->  NIL rplaca(e',v) c' (s e c.d)
; ------------------------------------------------------------------------------
_instr_RAP:
	cons	C, [D]		; C' <-- cons(cdr(C), D)
	mov		edx, [E]
	carcdr	eax, edx	; EAX <-- car(E), EDX <-- cdr(E)
	cons	eax, C		; EAX <-- cons(cdr(E), cons(cdr(C), D))
	carcdr	edx, S		; EDX <-- car(S), S' <-- cdr(S)
	carcdr	C, edx		; C' <-- car(car(S)), EDX <-- cdr(car(S))
	mov		[E], edx	; E' <-- EDX = cdr(car(S))
	carcdr	ecx, S		; ECX <-- car(cdr(S)), S' <-- cdr(cdr(S))
	cons	S, eax		; D' <-- cons(cdr(cdr(S)),
	mov		[D], S		;             cons(cdr(E), cons(cdr(C), D)))
	
	; car(EDX) <-- ECX, S used as temporary register
	mov		S, [dword values + edx * 4]
	and		S, 0x0000ffff
	shl		ecx, 16
	or		S, ecx
	mov		[dword values + edx * 4], S

	mov		S, 0		; S' <-- nil

	cons	eax, C		; EAX <-- cons(cdr(E)
	
	jmp		_cycle

; ------------------------------------------------------------------------------
; SEL - Select subcontrol
;
; TRANSITION:  (x.s) e (SEL ct cf.c) d  -->  s e c' (c.d)
;              where c' = ct if x = T, and c' = cf if x = F
; ------------------------------------------------------------------------------
_instr_SEL:
	mov		eax, C
	carcdr	edx, eax	; EDX <-- car(cdr(C))
	carcdr	ecx, eax	; ECX <-- car(cdr(cdr(C)), EAX <-- cdr(cdr(cdr(C)))
	cons	eax, [D]	
	mov		[D], eax	; D' <-- cons(cdr(cdr(cdr(C))), D)	
	carcdr	eax, S		; EAX <-- car(S), S' <-- cdr(S)
	push	S
	mov		S, [true]
	ivalue	S	
	ivalue	eax
	cmp		eax, S 
	cmove	C, edx		; IF car(S) == true THEN C' <-- car(cdr(C))
	cmovne	C, ecx		; IF car(S) != true THEN C' <-- car(cdr(cdr(C)))
	pop		S
	jmp		_cycle

; ------------------------------------------------------------------------------
; JOIN - Rejoin main control
;
; TRANSITION:  s e (JOIN) (c.d)  -->  s e c d
; ------------------------------------------------------------------------------
_instr_JOIN:
	mov		eax, [D]
	carcdr	C, eax
	mov		[D], eax 
	jmp		_cycle

; ------------------------------------------------------------------------------
; CAR - Take car of item on top of stack
;
; TRANSITION:  ((a.b) s) e (CAR.c) d  -->  (a.s) e c d
; ------------------------------------------------------------------------------
_instr_CAR:
	cdrcar	eax, S
	mov		dl, byte [flags + S]
	test	dl, SECD_ATOM
	jz		.endif
		call	_flush
		sys.write stderr, err_car, err_car_len
		sys.exit 1
.halt:
		jmp		.halt
.endif:
	car		S, S
	cons	S, eax 
	jmp		_cycle
	
; ------------------------------------------------------------------------------
; CDR - Take cdr of item on top of stack
;
; TRANSITION:  ((a.b) s) e (CAR.c) d  -->  (b.s) e c d
; ------------------------------------------------------------------------------
_instr_CDR:
	cdrcar	eax, S
	mov		dl, byte [flags + S]
	test	dl, SECD_ATOM
	jz		.endif
		call	_flush
		sys.write stderr, err_cdr, err_cdr_len
		sys.exit 1
.halt:
		jmp		.halt
.endif:
	cdr		S, S
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; ATOM - Apply atom predicate to top stack item
;
; TRANSITION:  (a.s) e (ATOM.c) d  -->  (t.s) e c d
;              where t = T if a is an atom and t = F if a is not an atom.
; ------------------------------------------------------------------------------
_instr_ATOM:
	carcdr	eax, S		; EAX <-- car(S), S' <-- cdr(S)
	mov		dl, byte [flags + eax]
						; DL <-- flags for EAX = car(S)
	test	dl, SECD_ATOM 
	cmovnz	eax, [true]		; IF (isnumber OR issymbol) THEN EAX <-- true
	cmovz	eax, [false]	; IF (!isnumber AND !issymbol) THEN EAX <-- false
	cons	eax, S
	mov		S, eax		; S' <-- cons(true/false, cdr(S))
	jmp		_cycle

; ------------------------------------------------------------------------------
; CONS - Form cons of top two stack items
;
; TRANSITION:  (a b.s) e (CONS.c) d  -->  ((a.b).s) e c d
; ------------------------------------------------------------------------------
_instr_CONS:
	cdrcar	edx, S
	carcdr	eax, edx	; EAX = car(cdr(S)), EDX = cdr(cdr(S)), S' = car(S)
	cons	S, eax
	cons	S, edx
	jmp		_cycle
	
; ------------------------------------------------------------------------------
; EQ - Apply eq predicate to top two stack items
;
; TRANSITION:  (a b.s) e (EQ.c) d  -->  ([a=b].s) e c d
; ------------------------------------------------------------------------------
_instr_EQ:
	carcdr	eax, S		; EAX <-- car(S), S' <-- cdr(S)
	mov		dl, byte [flags + eax]
	carcdr	ecx, S		; ECX <-- car(cdr(S)), S' <-- cdr(cdr(S))
	mov		dh, byte [flags + ecx]
	
	and		dx, 0x0101
	cmp		dx, 0x0101
	jne		.else
	ivalue	eax
	ivalue	ecx
	cmp		eax, ecx
	jne		.else		; IF isatom(car(S)) AND isatom(car(cdr(S))) AND
						;    ivalue(car(S)) == ivalue(car(cdr(S))) THEN ...
		mov		eax, [true]
		jmp		.endif
.else:
		mov		eax, [false]
.endif:
	cons	eax, S
	mov		S, eax		; S' <-- cons(T/F, cdr(cdr(S)))
	jmp		_cycle

; ------------------------------------------------------------------------------
; Arithmetic operation on non-numeric operands - push NIL onto stack as the
; result of this operation and jump to the top of the instruction cycle
; 
_arith_nonnum:
	mov		eax, 0
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; ADD - Add top two stack items
;
; TRANSITION:  (a b.s) e (ADD.c) d  -->  ([a+b].s) e c d
; ------------------------------------------------------------------------------
_instr_ADD:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	check_arith_args eax, edx
	ivalue	eax
	ivalue	edx
	add		eax, edx
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle
	
; ------------------------------------------------------------------------------
; SUB - Subtract top two stack items
;
; TRANSITION:  (a b.s) e (SUB.c) d  -->  ([a-b].s) e c d
; ------------------------------------------------------------------------------
_instr_SUB:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	check_arith_args eax, edx
	ivalue	eax
	ivalue	edx
	sub		eax, edx
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; MUL - Multiply top two stack items
;
; TRANSITION:  (a b.s) e (MUL.c) d  -->  ([a*b].s) e c d
; ------------------------------------------------------------------------------
_instr_MUL:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	check_arith_args eax, edx
	ivalue	eax
	ivalue	edx
	imul	edx
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; MUL - Extended multiply top two stack items
;
; TRANSITION:  (a b.s) e (MULX.c) d  -->  ((lo.hi).s) e c d
;              where lo is the least significant 32-bits of a*b and hi is the
;              most significant 32-bits of a*b
; ------------------------------------------------------------------------------
_instr_MULX:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	check_arith_args eax, edx
	ivalue	eax
	ivalue	edx
	imul	edx
	number	eax, eax
	number	edx, edx
	cons	eax, edx
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; DIV - Divide top two stack items
;
; TRANSITION:  (a b.s) e (DIV.c) d  -->  ([a/b].s) e c d
; ------------------------------------------------------------------------------
_instr_DIV:
	carcdr	ecx, S
	carcdr	eax, S		; EAX = car(cdr(S)), ECX = car(S), S' = cdr(cdr(S))
	check_arith_args eax, ecx
	ivalue	eax
	ivalue	ecx
	cdq					; Extend sign of EAX into all bits of EDX
	idiv	ecx			; Compute EAX <-- EDX:EAX / ECX
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; REM - Compute the remainder resulting from the division of the top two stack
;       items
;
; TRANSITION:  (a b.s) e (REM.c) d  -->  ([a%b].s) e c d
; ------------------------------------------------------------------------------
_instr_REM:
	carcdr	ecx, S
	carcdr	eax, S		; EAX = car(cdr(S)), ECX = car(S), S' = cdr(cdr(S))
	check_arith_args eax, ecx
	ivalue	eax
	ivalue	ecx
	mov		edx, eax
	sar		edx, 31		; Extend sign of EAX into all bits of EDX
	idiv	ecx			; Compute EDX <-- EDX:EAX % ECX
	number	edx, edx
	cons	edx, S
	mov		S, edx
	jmp		_cycle

; ------------------------------------------------------------------------------
; LEQ - Test whether the top stack item is less than or equal to the second item
;       on the stack
;
; TRANSITION:  (a b.s) e (REM.c) d  -->  ([a≤b].s) e c d
; ------------------------------------------------------------------------------
_instr_LEQ:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	mov		cl, byte [flags + edx]
	and		cl, SECD_TYPEMASK
	mov		ch, byte [flags + eax]
	and		ch, SECD_TYPEMASK
	cmp		ch, cl		; First compare types
	jne		.result		; If they have different types, we have a result, else..
	ivalue	eax
	ivalue	edx
	cmp		eax, edx	; Compare their values
.result:
	cmovle	eax, [true]
	cmovnle	eax, [false]
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; STOP - Halt the machine
;
; TRANSITION:  s e (STOP) d  -->  <undefined>
; ------------------------------------------------------------------------------
_instr_STOP:
	car		eax, S
	pop		edi
	pop		esi
	pop		ebx
	leave
	ret

; ------------------------------------------------------------------------------
; SYM - Apply issymbol predicate to top stack item
;
; TRANSITION:  (x.s) e (SYM.c) d  -->  (t.s) e c d
;              where t = T if x is a symbol, and t = F if x is not a symbol
; ------------------------------------------------------------------------------
_instr_SYM:
	carcdr	eax, S		; EAX <-- car(S), S' <-- cdr(S)
	mov		dl, byte [flags + eax]
						; DL <-- flags for EAX = car(S)
	and		dl, SECD_TYPEMASK
	cmp		dl, SECD_SYMBOL
	cmove	eax, [true]		; IF (issymbol) THEN EAX <-- true
	cmovne	eax, [false]	; IF (!issymbol) THEN EAX <-- false
	cons	eax, S
	mov		S, eax		; S' <-- cons(true/false, cdr(S))
	jmp		_cycle

; ------------------------------------------------------------------------------
; NUM - Apply isnumber predicate to top stack item
;
; TRANSITION:  (x.s) e (NUM.c) d  -->  (t.s) e c d
;              where t = T if x is a number, and t = F if x is not a number
; ------------------------------------------------------------------------------
_instr_NUM:
	carcdr	eax, S		; EAX <-- car(S), S' <-- cdr(S)
	mov		dl, byte [flags + eax]
						; DL <-- flags for EAX = car(S)
	and		dl, SECD_TYPEMASK
	cmp		dl, SECD_NUMBER
	cmove	eax, [true]		; IF (isnumber) THEN EAX <-- true
	cmovne	eax, [false]	; IF (!isnumber) THEN EAX <-- false
	cons	eax, S
	mov		S, eax		; S' <-- cons(true/false, cdr(S))
	jmp		_cycle

; ------------------------------------------------------------------------------
; GET - Push ASCII value of a character from stdin onto stack
;
; TRANSITION:  s e (GET.c) d  -->  (x.s) e c d
;              where x is the ASCII value of the character read from stdin
; ------------------------------------------------------------------------------
_instr_GET:
	pushsecd
	call	_getchar
	popsecd
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; PUT - Pop ASCII value from stack and write it to stdout
;
; TRANSITION:  (x.s) e (PUT.c) d  -->  s e c d
; SIDE EFFECT:  The character with the ASCII value x is printed to stdout
; ------------------------------------------------------------------------------
_instr_PUT:
	car		eax, S
	ivalue	eax
	and		eax, 0x000000ff
	pushsecd
	push	eax
	call	_putchar
	add		esp, 4
	popsecd
	jmp		_cycle

; ------------------------------------------------------------------------------
; PEXP - Print expression on top of stack to stdout
;
; TRANSITION:  (x.s) e (PEXP.c) d  -->  (x.s) e c d
; SIDE EFFECT:  The expression x is printed to stdout
; ------------------------------------------------------------------------------
_instr_PEXP:
    car		eax, S
	pushsecd
	push	eax
	call	_putexp
	add		esp, 4
	popsecd
	jmp		_cycle

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
	carcdr	edx, S		; EDX <-- car(S), S' <-- cdr(S)
	carcdr	C, edx		; C' <-- car(car(S)), EDX <-- cdr(car(S))
	car		ecx, S		; ECX <-- car(cdr(S))
	cons	ecx, edx
	mov		[E], ecx	; E' <-- cons(car(cdr(S)), cdr(car(S)))
	mov		S, 0		; S' <-- nil
	jmp		_cycle

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
	mov		eax, C
	carcdr	edx, eax	; EDX <-- car(cdr(C))
	car		ecx, eax	; ECX <-- car(cdr(cdr(C))
	carcdr	eax, S		; EAX <-- car(S), S' <-- cdr(S)
	push	S
	mov		S, [true]
	ivalue	S	
	ivalue	eax
	cmp		eax, S 
	cmove	C, edx		; IF car(S) == true THEN C' <-- car(cdr(C))
	cmovne	C, ecx		; IF car(S) != true THEN C' <-- car(cdr(cdr(C)))
	pop		S
	jmp		_cycle

; ------------------------------------------------------------------------------
; CVEC - Create vector
;
; TRANSITION:  (n.s) e (CVEC.c) d  -->  (v.s) e c d
;              where v is a newly allocated vector of length n
; ------------------------------------------------------------------------------
_instr_CVEC:
	carcdr	eax, S		; EAX <-- number of elements in vector
	ivalue	eax
	shl		eax, 1		; EAX <-- 2*length == # bytes to allocate
	call	_malloc
	alloc	eax, eax, SECD_VECTOR
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; VSET - Set element of vector
;
; TRANSITION:  (v i x.s) e (VSET.c) d  -->  (v.s) e c d
; SIDE EFFECT:  v[i] <-- x
; ------------------------------------------------------------------------------
_instr_VSET:
	carcdr	eax, S
	carcdr	ecx, S
	push	eax
	ivalue	eax	
	ivalue	ecx
	mov		edx, eax
	call	_heap_item_length	; Does not clobber ECX, EDX
	shr		eax, 1
	cmp		ecx, eax
	jb		.endif
		add		esp, 4
		jmp		_index_out_of_bounds
.endif:
	carcdr	eax, S
	mov		word [edx + ecx*2], ax
	pop		eax
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; VREF - Get element of vector
;
; TRANSITION:  (v i.s) e (VREF.c) d  -->  (v[i].s) e c d
; ------------------------------------------------------------------------------
_instr_VREF:
	carcdr	eax, S
	carcdr	ecx, S
	ivalue	eax	
	ivalue	ecx
	mov		edx, eax
	call	_heap_item_length	; Does not clobber ECX, EDX
	shr		eax, 1
	cmp		ecx, eax
	jb		.endif	
		jmp		_index_out_of_bounds
.endif:
	mov		eax, 0
	mov		ax, word [edx + ecx*2]
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; VLEN - Get length of vector
;
; TRANSITION:  (v.s) e (VLEN.c) d  -->  (n.s) e c d
;              where n is the number of elements in v
; ------------------------------------------------------------------------------
_instr_VLEN:
	carcdr	eax, S
	ivalue	eax
	call	_heap_item_length
	shr		eax, 1
	number	eax, eax
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; VCPY - Bulk copy between vectors
;
; TRANSITION:  (v i w j n.s) e (VCPY.c) d  -->  (v.s) e c d
; SIDE EFFECT:  w[j+k] <-- v[i+k] for all k, 0 ≤ k < n
; ------------------------------------------------------------------------------
_instr_VCPY:
	push	esi
	push	edi
	carcdr	eax, S
	carcdr	ecx, S
	ivalue	eax
	ivalue	ecx
	lea		esi, [eax + ecx*2]
	call	_heap_item_length
	shr		eax, 1
	sub		eax, ecx
	mov		edx, eax
	carcdr	eax, S
	carcdr	ecx, S
	push	eax
	ivalue	eax
	ivalue	ecx
	lea		edi, [eax + ecx*2]
	call	_heap_item_length
	shr		eax, 1
	sub		eax, ecx
	carcdr	ecx, S
	ivalue	ecx
	cmp		ecx, eax
	ja		.out_of_bounds
	cmp		ecx, edx
	ja		.out_of_bounds
	jmp		.loop
.out_of_bounds:
	pop		eax
	pop		edi
	pop		esi
	jmp		_index_out_of_bounds
	cld
.loop:
		jcxz	.endloop
		rep		movsw
		jmp		.loop
.endloop:
	pop		eax
	pop		edi
	pop		esi	
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; CBIN - Create binary blob
;
; TRANSITION:  (n.s) e (CBIN.c) d  -->  (b.s) e c d
;              where b is a newly allocated n-byte binary blob
; ------------------------------------------------------------------------------
_instr_CBIN:
	carcdr	eax, S		; EAX <-- length of binary
	ivalue	eax
	call	_malloc
	alloc	eax, eax, SECD_BINARY
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; BSET - Set byte in binary blob
;
; TRANSITION:  (b i x.s) e (BSET.c) d  -->  (b.s) e c d
; SIDE EFFECT:  [b+i] <-- x
; ------------------------------------------------------------------------------
_instr_BSET:
	carcdr	eax, S
	carcdr	ecx, S
	push	eax
	ivalue	eax	
	ivalue	ecx
	mov		edx, eax
	call	_heap_item_length	; Does not clobber ECX, EDX
	cmp		ecx, eax
	jb		.endif
		add		esp, 4
		jmp		_index_out_of_bounds
.endif:
	carcdr	eax, S
	ivalue	eax
	mov		byte [edx + ecx], al
	pop		eax
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; BGET - Get byte in binary blob
;
; TRANSITION:  (b i.s) e (BGET.c) d  -->  ([b+i].s) e c d
; ------------------------------------------------------------------------------
_instr_BREF:
	carcdr	eax, S
	carcdr	ecx, S
	ivalue	eax	
	ivalue	ecx
	mov		edx, eax
	call	_heap_item_length	; Does not clobber ECX, EDX
	cmp		ecx, eax
	jb		.endif	
		jmp		_index_out_of_bounds
.endif:
	mov		eax, 0
	mov		al, byte [edx + ecx]
	number	eax, eax
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; BLEN - Get size of binary blob
;
; TRANSITION:  (b.s) e (BLEN.c) d  -->  (n.s) e c d
;              where n is the length of b, in bytes
; ------------------------------------------------------------------------------
_instr_BLEN:
	carcdr	eax, S
	ivalue	eax
	call	_heap_item_length
	number	eax, eax
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; BCPY - Bulk copy between binary blobs
;
; TRANSITION:  (b1 i b2 j n.s) e (BCPY.c) d  -->  (b1.s) e c d
; SIDE EFFECT:  b2[j+k] <-- b1[i+k] for all k, 0 ≤ k < n
; ------------------------------------------------------------------------------
_instr_BCPY:
	push	esi
	push	edi
	carcdr	eax, S
	carcdr	ecx, S
	ivalue	eax
	ivalue	ecx
	lea		esi, [eax + ecx]
	call	_heap_item_length
	sub		eax, ecx
	mov		edx, eax
	carcdr	eax, S
	carcdr	ecx, S
	push	eax
	ivalue	eax
	ivalue	ecx
	lea		edi, [eax + ecx]
	call	_heap_item_length
	sub		eax, ecx
	carcdr	ecx, S
	ivalue	ecx
	cmp		ecx, eax
	ja		.out_of_bounds
	cmp		ecx, edx
	ja		.out_of_bounds
	jmp		.loop
.out_of_bounds:
	pop		eax
	pop		edi
	pop		esi
	jmp		_index_out_of_bounds
	cld
.loop:
		jcxz	.endloop
		rep		movsb
		jmp		.loop
.endloop:
	pop		eax
	pop		edi
	pop		esi	
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

; ------------------------------------------------------------------------------
; BS16 - Set 16-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i x.s) e (BSET.c) d  -->  (b.s) e c d
; SIDE EFFECT:  [b+i*2]@2 <-- x
; ------------------------------------------------------------------------------
_instr_BS16:
	jmp		_illegal

; ------------------------------------------------------------------------------
; BG16 - Get 16-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i.s) e (BGET.c) d  -->  ([b+i*2]@2.s) e c d
; ------------------------------------------------------------------------------
_instr_BR16:
	jmp		_illegal

; ------------------------------------------------------------------------------
; BS32 - Set 32-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i x.s) e (BSET.c) d  -->  (b.s) e c d
; SIDE EFFECT:  [b+i*4]@4 <-- x
; ------------------------------------------------------------------------------
_instr_BS32:
	jmp		_illegal

; ------------------------------------------------------------------------------
; BG32 - Get 32-bit value in binary blob                           UNIMPLEMENTED
;
; TRANSITION:  (b i.s) e (BGET.c) d  -->  ([b+i*4]@4.s) e c d
; ------------------------------------------------------------------------------
_instr_BR32:
	jmp		_illegal

_index_out_of_bounds:
	call	_flush
	sys.write stderr, err_oob, err_oob_len
	sys.exit 1
.halt:
	jmp		.halt
	

; ==============================================================================
; Garbage Collection
;
; We use a mark-and-sweep garbage collector to find unreferenced cells.  We
; begin by marking the cells referenced by the registers of the machine: S, E,
; C, D, true, and false.  Whenever we mark a cons cell, we recursively mark that
; cell's car and cdr (if they are not already marked).  After this phase is
; complete, we iterate over all cells and push the unmarked cells onto the free
; list.
; 

; ------------------------------------------------------------------------------
; Traces referenced cells starting with the registers of the SECD machine
;
_trace:
	push	eax			; Save current SECD-machine state
	push	ecx
	push	edx
	push	S
	push	C

	; Clear all marks
	mov		ecx, 65536
	mov		edx, dword flags
.loop_clearmarks:
		and		[edx], byte ~SECD_MARKED
		inc		edx
		dec		ecx
		jnz		.loop_clearmarks

    ; Trace from root references (SECD-machine registers)
	mov		eax, S
	call	_mark
	mov		eax, C
	call	_mark
	mov		eax, [E]
	call	_mark
	mov		eax, [D]
	call	_mark
	mov		eax, [true]
	call	_mark
	mov		eax, [false]
	call	_mark
	mov		eax, 0
	call	_mark

; Sanity check -- scan free list for marked cells.  There should not be any.
%ifdef DEBUG
	mov		eax, ff
.loop_checkff:
		cmp		eax, 0								; while (eax != 0)
		je		.done
		test	byte [flags + eax], SECD_MARKED		;   if cell marked...
		jnz		.error								;	  break to error
		mov		eax, dword [values + 4 * eax]		;   advance to next cell
		and		eax, 0xffff
		jmp		.loop_checkff						; end while
.error:
	call	_flush									; found in-use cell in free
	sys.write stderr, err_ff, err_ff_len			; list.
	sys.exit 1
.halt:
	jmp		.halt

.done:
%endif	; DEBUG

	pop		C			; Restore SECD-machine state
	pop		S
	pop		edx
	pop		ecx
	pop		eax
	ret

; ------------------------------------------------------------------------------
; Find and mark referenced cells recursively
; EXPECTS eax = the index of the cell from which to start tracing
;
_mark:
	mov		dl, byte [flags + eax]			; DL <-- flags for current cell
	test	dl, SECD_MARKED
	jz		.if
	ret										; quit if cell already marked
	.if:
		or		dl, SECD_MARKED
		mov		byte [flags + eax], dl		; mark this cell
		test	dl, SECD_ATOM
		jnz		.else						; if this is a cons cell then...
			cdrcar	edx, eax				; recurse on car and cdr
			push	edx
			call	_mark
			pop		eax
			call	_mark
			jmp		.endif
	.else:
		test	dl, SECD_HEAP				; if cell is a heap reference...
		jz		.endif
		push	ebx
		mov		ebx, eax
		ivalue	eax
		test	byte [gcheap], HEAP_FORWARD
		jz		.endif_heap_forward
			call	_heap_forward			; update reference if forwarded
			mov		[values + ebx * 4], eax			
	.endif_heap_forward:	
		test	byte [gcheap], HEAP_MARK
		jz		.endif_heap_mark			; if heap item not marked then...
			call	_heap_mark				; mark the heap item
	.endif_heap_mark:
		and		dl, SECD_TYPEMASK
		cmp		dl, SECD_VECTOR
		jne		.endif_vector				; if cell is a vector reference...
			mov		eax, ebx
			call	_heap_item_length
			mov		ecx, eax
			shr		ecx, 1
		.loop:								; recurse on all entries in vector
				mov		eax, 0
				mov		ax, word [ebx]
				add		ebx, 2
				push	ecx
				call	_mark
				pop		ecx
				loop	.loop
	.endif_vector:
		pop		ebx	
.endif:
	ret

; ------------------------------------------------------------------------------
; Finds unused cells and adds them to the free list.
;
_gc:
	call	_trace

	push	eax
	push	ecx
	push	edx
	push	S
	push	C

	mov		ff, 0
	mov		edx, 0
	mov		ecx, 65535
.loop_scan:
		mov		al, byte [flags + ecx]
		test	al, SECD_MARKED
		jnz		.endif
			mov		dword [values + ecx * 4], ff
			mov		byte [flags + ecx], byte SECD_CONS
			mov		ff, ecx		
			inc		edx
	.endif:
		dec		ecx
		jnz		.loop_scan

	mov		dword [free], edx

	cmp		ff, 0
	je		.out_of_space

	pop		C
	pop		S
	pop		edx
	pop		ecx
	pop		eax

	ret

.out_of_space:
	call	_flush
	sys.write stderr, err_hf, err_hf_len
	sys.exit 1
.halt:
	jmp		.halt	

; ------------------------------------------------------------------------------
; Garbage collection for heap (vectors and binary blobs)              UNFINISHED
;
_heap_gc:
	mov		byte [gcheap], HEAP_MARK
	call	_trace
	call	_heap_sweep
	mov		byte [gcheap], HEAP_FORWARD
	call	_gc
	mov		byte [gcheap], 0
	ret

; ------------------------------------------------------------------------------
; Allocate a block of memory on the heap                              UNFINISHED
;
_malloc:
	push	eax
	call	_heap_alloc
	cmp		eax, 0
	jnz		.done
	call	_heap_gc
	mov		eax, [esp]
	call	_heap_alloc
	cmp		eax, 0
	jnz		.done
	call	_flush
	sys.write stderr, err_hf, err_hf_len
	sys.exit 1
.halt:
	jmp		.halt	
.done:
	add		esp, 4
	ret

