; Reserved registers:
; EBX - (S)tack
; ESI - (C)ontrol
; EDI - Head of free list (ff)

%include 'secd.inc'
%include 'system.inc'

%define SECD_MARKED 0x80

%define S ebx
%define C esi
%define ff edi

%macro car 2 
	mov		%1, [dword values + %2 * 4]
	shr		%1, 16
%endmacro

%macro cdr 2
	mov		%1, [dword values + %2 * 4]
	and		%1, 0xffff
%endmacro

%macro carcdr 2
	mov		%2, [dword values + %2 * 4]
	mov		%1, %2
	shr		%1, 16
	and		%2, 0xffff
%endmacro

%macro cdrcar 2
	mov		%2, [dword values + %2 * 4]
	mov		%1, %2
	and		%1, 0xffff
	shr		%2, 16
%endmacro

%macro ivalue 1
	mov		%1, [dword values + %1 * 4]
%endmacro

%macro alloc 3
	cmp		ff, 0
	jne		%%nogc
	call	_gc
%%nogc:
	mov		[flags + ff], byte %3
%ifidni %1,%2
	xchg	%1, ff
	xchg	ff, [dword values + %1 * 4]
	and		ff, 0xffff
%else
	mov		%1, ff
	cdr		ff, ff
	mov		[dword values + %1 * 4], %2
%endif
%endmacro

%macro cons 2
	shl		%1, 16
	or		%1, %2
	alloc	%1, %1, SECD_CONS
%endmacro

%macro number 2
	alloc	%1, %2, SECD_NUMBER
%endmacro

%macro symbol 2
	alloc	%1, %2, SECD_SYMBOL
%endmacro


segment .data
tstr		db		"T"
tstr_len	equ		$ - tstr
fstr		db		"F"
fstr_len	equ		$ - fstr
nilstr		db		"NIL"
nilstr_len	equ		$ - nilstr
err_ii		db		"Illegal instruction", 10
err_ii_len	equ		$ - err_ii
err_hf		db		"Out of heap space", 10
err_hf_len	equ		$ - err_hf
err_car		db		"Attempt to CAR an atom", 10
err_car_len	equ		$ - err_car
err_cdr		db		"Attempt to CDR an atom", 10
err_cdr_len	equ		$ - err_cdr


segment .bss
	global nil
values		resd	65536	; Storage for cons cells and ivalues
flags		resb	65536	; Storage for isatom and isnumber bits

E			resd	1		; (E)nvironment register
D			resd	1		; (D)ump register
true		resd	1		; true register
false		resd	1		; false register
nil			resd	1		; nil register
Sreg		resd	1
Creg		resd	1
ffreg		resd	1


segment .text
	global _exec, _flags, _car, _cdr, _ivalue, _issymbol, _isnumber, \
		_iscons, _cons, _svalue, _init, _number, _symbol
	extern _store, _getchar, _putchar

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
	symbol	eax, eax
	mov		[nil], eax
	mov		[ffreg], ff
	leave
	ret

_exec:
	enter	0, 0
	push	ebx
	push	esi
	push	edi
	mov		ff, [ffreg]
	mov		eax, [nil]
	mov		C, [ebp + 8]	; C <-- fn
	and		C, 0xffff
	mov		S, [ebp + 12]	; S <-- args
	and		S, 0xffff
	mov		[E], eax
	mov		[D], eax
	cons	S, eax
	
_cycle:
	carcdr	eax, C
	ivalue	eax	
	cmp		eax, 1
	jl		_illegal
	cmp		eax, dword numinstr
	jge		_illegal	
	jmp		[dword _instr + eax * 4]

_illegal:
	push	dword err_ii_len
	push	dword err_ii
	push	dword stderr
	sys.write
	add		esp, 12
	push	dword 1
	sys.exit
.stop:
	jmp		.stop
	

_instr \
	dd	0, \
		_instr_LD  , _instr_LDC , _instr_LDF , _instr_AP  , _instr_RTN , \
		_instr_DUM , _instr_RAP , _instr_SEL , _instr_JOIN, _instr_CAR , \
		_instr_CDR , _instr_ATOM, _instr_CONS, _instr_EQ  , _instr_ADD , \
		_instr_SUB , _instr_MUL , _instr_DIV , _instr_REM , _instr_LEQ , \
		_instr_STOP, _instr_SYM , _instr_NUM , _instr_GET , _instr_PUT
numinstr	equ		($ - _instr) >> 2
	
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
	
_instr_LDC:
	carcdr	eax, C
	xchg	S, eax
	cons	S, eax
	jmp		_cycle

_instr_LDF:
	carcdr	eax, C
	cons	eax, [E]
	cons	eax, S
	mov		S, eax
	jmp		_cycle

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
	mov		S, [nil]	; S' <-- nil
	jmp		_cycle
	
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
	
_instr_DUM:
	mov		eax, [nil]
	cons	eax, [E]
	mov		[E], eax	; E' <-- cons(nil, E)
	jmp		_cycle
	
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

	mov		S, [nil]	; S' <-- nil

	cons	eax, C		; EAX <-- cons(cdr(E)
	
	jmp		_cycle

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

_instr_JOIN:
	mov		eax, [D]
	carcdr	C, eax
	mov		[D], eax 
	jmp		_cycle

_instr_CAR:
	cdrcar	eax, S
	mov		edx, [flags + S]
	test	edx, SECD_ATOM
	jz		.endif
		push	dword err_car_len
		push	dword err_car
		push	dword stderr
		sys.write
		add		esp, 12
		push	dword 1
		sys.exit
		add		esp, 4
.halt:
		jmp		.halt
.endif:
	car		S, S
	cons	S, eax 
	jmp		_cycle
	
_instr_CDR:
	cdrcar	eax, S
	mov		edx, [flags + S]
	test	edx, SECD_ATOM
	jz		.endif
		push	dword err_cdr_len
		push	dword err_cdr
		push	dword stderr
		sys.write
		add		esp, 12
		push	dword 1
		sys.exit
.halt:
		jmp		.halt
.endif:
	cdr		S, S
	cons	S, eax
	jmp		_cycle

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

_instr_CONS:
	cdrcar	edx, S
	carcdr	eax, edx	; EAX = car(cdr(S)), EDX = cdr(cdr(S)), S' = car(S)
	cons	S, eax
	cons	S, edx
	jmp		_cycle
	
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

_instr_ADD:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	add		eax, edx
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle
	
_instr_SUB:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	sub		eax, edx
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

_instr_MUL:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	imul	edx
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

_instr_DIV:
	carcdr	ecx, S
	carcdr	eax, S		; EAX = car(cdr(S)), ECX = car(S), S' = cdr(cdr(S))
	ivalue	eax
	ivalue	ecx
	cdq					; Extend sign of EAX into all bits of EDX
	div		ecx			; Compute EAX <-- EDX:EAX / ECX
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

_instr_REM:
	carcdr	ecx, S
	carcdr	eax, S		; EAX = car(cdr(S)), ECX = car(S), S' = cdr(cdr(S))
	ivalue	eax
	ivalue	ecx
	mov		edx, eax
	sar		edx, 31		; Extend sign of EAX into all bits of EDX
	div		ecx			; Compute EDX <-- EDX:EAX % ECX
	number	edx, edx
	cons	edx, S
	mov		S, edx
	jmp		_cycle

_instr_LEQ:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S' = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	cmp		eax, edx
	cmovle	eax, [true]
	cmovnle	eax, [false]
	cons	eax, S
	mov		S, eax
	jmp		_cycle

_instr_STOP:
	car		eax, S
	pop		edi
	pop		esi
	pop		ebx
	leave
	ret

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

_instr_GET:
	call	_getchar
	number	eax, eax
	cons	eax, S
	mov		S, eax
	jmp		_cycle

_instr_PUT:
	car		eax, S
	ivalue	eax
	and		eax, 0x000000ff
	push	eax
	call	_putchar
	add		esp, 4
	jmp		_cycle
			


_gc:
	push	eax
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

	test	S, 0xffff0000
	jz		.endif1
		mov		eax, S
		shr		eax, 16
		call	_mark
		and		S, 0xffff
.endif1:
	mov		eax, S
	call	_mark
	
	test	C, 0xffff0000
	jz		.endif2
		mov		eax, C
		shr		eax, 16
		call	_mark
		and		C, 0xffff
.endif2:
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
	mov		eax, [nil]
	call	_mark

	mov		ecx, 65535
.loop_scan:
		mov		al, byte [flags + ecx]
		test	al, SECD_MARKED
		jnz		.endif
			mov		dword [values + ecx * 4], ff
			mov		ff, ecx		
	.endif:
		dec		ecx
		jnz		.loop_scan

	pop		C
	pop		S
	pop		edx
	pop		ecx
	pop		eax

	cmp		ff, 0
	je		.out_of_space
	ret

.out_of_space:
	push	dword err_hf_len
	push	dword err_hf
	push	dword stderr
	sys.write
	add		esp, 12
	push	dword 1
	sys.exit
	add		esp, 4
.halt:
	jmp		.halt	


_mark:
	mov		dl, byte [flags + eax]
	test	dl, SECD_MARKED
	jnz		.endif
		or		dl, SECD_MARKED
		mov		byte [flags + eax], dl
		test	dl, SECD_ATOM
		jnz		.endif
			cdrcar	edx, eax
			push	edx
			call	_mark
			pop		eax
			call	_mark
.endif:
	ret
