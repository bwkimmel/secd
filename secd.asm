segment .bss
values		resd	65536
flags		resb	16384

E			resd	1
D			resd	1
true		resd	1
false		resd	1
nil			resd	1

segment .text

_exec:

	; EAX - (S)tack
	; EBX - (E)nvironment
	; ESI - (C)ontrol
	; EDI - (D)ump
	; EDX - (W)orking

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

%macro newcons 1
	mov		%1, ff 
	cdr		ff, ff
%endmacro

%macro cons 2
	shl		%1, 16
	or		%1, %2
	mov		[dword values + ff * 4], %1
	mov		%1, ff
	cdr		ff, ff
%endmacro

%macro number 1
	mov		[dword values + ff * 4], %1
	mov		%1, ff
	cdr		ff, ff
%endmacro

.cycle:
	carcdr	eax, C
	ivalue	eax	
	lea		eax, [dword _instr + eax * 4]
	call	eax
	jmp		.cycle

_instr \
	dd	0, \
		_instr_LD  , _instr_LDC , _instr_LDF , _instr_AP  , _instr_RTN , \
		_instr_DUM , _instr_RAP , _instr_SEL , _instr_JOIN, _instr_CAR , \
		_instr_CDR , _instr_ATOM, _instr_CONS, _instr_EQ  , _instr_ADD , \
		_instr_SUB , _instr_MUL , _instr_DIV , _instr_REM , _instr_LEQ , \
		_instr_STOP
	
_instr_LD:
_instr_LDC:
	cdrcar	C, eax
	xchg	S, eax
	cons	S, eax
	ret

_instr_LDF:
_instr_AP:
_instr_RTN:
_instr_DUM:
_instr_RAP:
_instr_SEL:

_instr_JOIN:
	mov		eax, [D]
	carcdr	C, eax
	mov		[D], eax 
	ret

_instr_CAR:
	cdrcar	eax, S
	car		S, S
	cons	S, eax 
	ret
	
_instr_CDR:
	cdrcar	eax, S
	cdr		S, S
	cons	S, eax
	ret

_instr_ATOM:
	

_instr_CONS:
	cdrcar	edx, S
	carcdr	eax, edx	; EAX = car(cdr(S)), EDX = cdr(cdr(S)), S = car(S)
	cons	S, eax
	cons	S, edx
	ret
	
_instr_EQ:

_instr_ADD:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	add		eax, edx
	number	eax
	cons	eax, S
	mov		S, eax
	ret
	
_instr_SUB:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	sub		eax, edx
	number	eax
	cons	eax, S
	mov		S, eax
	ret

_instr_MUL:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	imul	edx
	number	eax
	cons	eax, S
	mov		S, eax
	ret

_instr_DIV:
	carcdr	ecx, S
	carcdr	eax, S		; EAX = car(cdr(S)), ECX = car(S), S = cdr(cdr(S))
	ivalue	eax
	ivalue	ecx
	mov		edx, eax
	sar		edx, 31		; Extend sign of EAX into all bits of EDX
	div		ecx			; Compute EAX <-- EDX:EAX / ECX
	number	eax
	cons	eax, S
	mov		S, eax
	ret

_instr_REM:
	carcdr	ecx, S
	carcdr	eax, S		; EAX = car(cdr(S)), ECX = car(S), S = cdr(cdr(S))
	ivalue	eax
	ivalue	ecx
	mov		edx, eax
	sar		edx, 31		; Extend sign of EAX into all bits of EDX
	div		ecx			; Compute EDX <-- EDX:EAX % ECX
	number	edx
	cons	edx, S
	mov		S, edx
	ret

_instr_LEQ:
	carcdr	edx, S
	carcdr	eax, S		; EAX = car(cdr(S)), EDX = car(S), S = cdr(cdr(S))
	ivalue	eax
	ivalue	edx
	cmp		eax, edx
	cmovle	eax, [true]
	cmovnle	eax, [false]
	cons	eax, S
	mov		S, eax
	ret

_instr_STOP:



