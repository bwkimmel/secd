segment .data

hello		db		'Hello, world, %x', 10, 0


segment .text
	global	_asm_main
	extern	_printf, _cons_alloc, _cons_free, _cons_init

_asm_main:
	enter	0, 0
	call	_cons_init
	mov		ecx, 5;16385
.loop
	push	ecx
	call	_cons_alloc
	push	eax
	sub		esp,8
	push	eax
	push	dword hello
	call	_printf
	add		esp,16 
	pop		eax
	;call	_cons_free
	pop		ecx
	loop	.loop
	mov		eax, 0
	leave
	ret
