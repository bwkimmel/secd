%include "lisp.inc"
%include "data.inc"
%include "cons.inc"

segment .data
primitives		dd		_car, _cdr, \
						_caar, _cadr, _cdar, _cddr, \
						_caaar, _caadr, _cadar, _caddr, \
						_cdaar, _cdadr, _cddar, _cdddr, \
						_caaaar, _caaadr, _caadar, _caaddr, \
						_cadaar, _cadadr, _caddar, _cadddr, \
						_cdaaar, _cdaadr, _cdadar, _cdaddr, \
						_cddaar, _cddadr, _cdddar, _cddddr
end_primitives	equ		$
num_primitives	equ		(end_primitives - primitives) >> 2


segment .text
	global _car
	global _cdr
	extern cons

_evaluate_atom:

_eval:
	enter	4, 0

	lcons	eax

	; EAX = cons cell to evaluate
	mov		[esp + 0], eax
	car		eax

	mov		edx, eax
	and		edx, CONS_MASK
	cmp		edx, CONS_FLAG
	jne		.car_not_cons

	call	_eval

.car_not_cons:
	mov		edx, eax
	and		edx, ATOM_MASK
	cmp		edx, ATOM_FLAG
	jne		.car_not_atom

	unmask_atom	eax
	sub		eax, num_primitives	
	jge		.atom_not_primitive

	mov		edx, [end_primitives + eax*4]

	mov		eax, [esp + 0]
	cdr		eax
	call	edx

	leave
	ret

.atom_not_primitive

	

.car_not_atom

	; The head of the list did not evaluate
	; to an atom.  Display an error message.

	leave
	ret

_add:
	enter	8, 0

	mov		[esp + 0], 0

.loop:
		lcons	eax
		
		mov		[esp + 4], eax
		car		eax

		call	_eval_int

		unmask_int eax
		add		[esp + 0], eax

		mov		eax, [esp + 4]
		cdr		eax
		cmp		eax, NULL
		jne		.loop

	mov		eax, edx
	mask_int eax
	leave
	ret
	
_mul:
	enter	4, 0
	lcons	eax
	mov		edx, eax
	car		edx
	unmask_int edx

.loop: 
		cdr		eax
		cmp		eax, NULL
		je		.endloop

		mov		ecx, eax
		car		ecx
		unmask_int ecx
		jcxz	.zero

		jmp		.loop

.zero:
	mov		edx, INT_ZERO

.endloop:
	mask_int edx
	mov		eax, edx
	leave
	ret
	
	
_eval_int:
	mov		edx, eax
	and		edx, INT_MASK
	cmp		edx, INT_FLAG
	jne		.eval
	ret
.eval:
	call	_eval
	mov		edx, eax
	and		edx, INT_MASK
	cmp		edx, INT_FLAG
	jne		.error
	ret
.error:
	; Print error message
	ret
	
	

_car:
	lcar	eax
	ret

_cdr:
	lcdr	eax
	ret

_caar:
	lcar	eax
	lcar	eax
	ret

_cadr:
	lcdr	eax
	lcar	eax
	ret

_cdar:
	lcar	eax
	lcdr	eax
	ret

_cddr:
	lcdr	eax
	lcdr	eax
	ret

_caaar:
	lcar	eax
	lcar	eax
	lcar	eax
	ret

_caadr:
	lcdr	eax
	lcar	eax
	lcar	eax
	ret

_cadar:
	lcar	eax
	lcdr	eax
	lcar	eax
	ret

_caddr:
	lcdr	eax
	lcdr	eax
	lcar	eax
	ret

_cdaar:
	lcar	eax
	lcar	eax
	lcdr	eax
	ret

_cdadr:
	lcdr	eax
	lcar	eax
	lcdr	eax
	ret

_cddar:
	lcar	eax
	lcdr	eax
	lcdr	eax
	ret

_cdddr:
	lcdr	eax
	lcdr	eax
	lcdr	eax
	ret
