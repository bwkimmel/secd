segment .data

hello		db		'Hello, world, %x', 10, 0


segment .text
	global	_asm_main
	extern	_printf, cons_alloc, cons_free

_asm_main:
	enter	0, 0
	mov		ecx, 16385
.loop
	push	ecx
	call	cons_alloc
	push	eax
	sub		esp,8
	push	eax
	push	dword hello
	call	_printf
	add		esp,16 
	pop		eax
	call	cons_free
	pop		ecx
	loop	.loop
	mov		eax, 0
	leave
	ret
