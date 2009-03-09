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
	lcons	eax
	mov		edx, eax
	car		eax
	cdr		edx
	add_masked_ints eax, edx
	ret

_mul:
	lcons	eax
	mov		edx, eax

	car		eax
	unmask_int eax

	cdr		edx
	unmask_int edx

	mul		eax, edx
	mask_int eax
	
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
