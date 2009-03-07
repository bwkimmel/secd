%include "lisp.inc"

segment .text
	global _car
	global _cdr

_car:
	car		eax
	ret	

_cdr:
	cdr		eax
	ret
