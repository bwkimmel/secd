%include 'system.inc'

segment .data
	extern	tt_eof, tt_num, tt_alpha, tt_delim, nil
hello		db		"Hello, World!", 10
hello_len	equ		$ - hello
teststr		db		"xxx", 0, "yyy"
teststr_len	equ		$ - teststr

segment .bss
buf			resb	1024

segment .text
	global start
	extern _getchar, _putchar, _flush, _gettoken, _puttoken, _tointeger, \
		_tostring, _store, _init_strings, _init, _cons, _car, _cdr, _ivalue, \
		_number
	extern _putexp

start:
	push	dword hello_len
	push	dword hello
	push	dword stdout
	sys.write
	add		esp, 12
	call	_test6
	push	dword 0
	sys.exit

_test1:
	enter	0, 0
.loop:
		push	dword 0
		push	dword 1024
		push	dword buf
		push	dword stdin
		sys.read
		add		esp, 16
		cmp		eax, 0
		jle		.done
		push	dword eax 
		push	dword buf
		push	dword stdout
		sys.write
		jmp		.loop
.done:
	leave
	ret
	
_test2:
	enter	0, 0
.loop:
		call	_getchar
		push	eax
		call	_putchar
		add		esp, 4
		call	_flush
		jmp		.loop
	leave
	ret

_test3:
	enter	0, 0
	push	esi
	push	ebx
	sub		esp, 4
	push	esp
	push	dword 1024
	push	dword buf
	call	_gettoken
	add		esp, 12
.loop:
		mov		ebx, [esp]
		cmp		ebx, dword tt_eof
		je		.endloop

		push	eax
		push	dword 1
		push	dword teststr
		call	_puttoken
		add		esp, 8
		pop		eax

		push	eax
		push	dword buf
		call	_puttoken
		add		esp, 8

		push	dword 100
		push	ebx
		call	_puttoken
		add		esp, 8

		call	_flush

		push	esp 
		push	dword 1024
		push	dword buf
		call	_gettoken
		add		esp, 12
		jmp		.loop
.endloop:
	
	add		esp, 4
	pop		ebx
	pop		esi
	leave
	ret

_test4:
	enter	0, 0
	push	esi
	push	ebx
	call	_init_strings
	sub		esp, 4
	push	esp
	push	dword 1024
	push	dword buf
	call	_gettoken
	add		esp, 12
.loop:
		mov		ebx, [esp]
		cmp		ebx, dword tt_eof
		jne		.continue
		jmp		.endloop
.continue:

		push	eax
		push	dword buf
		call	_puttoken
		add		esp, 4
		pop		eax

		cmp		ebx, tt_num
		jne		.else
			push	dword 1024	
			push	dword buf
			call	_tointeger
			add		esp, 8
;			push	eax
;			mov		eax, 0
;			mov		ecx, 256
;			mov		edi, dword buf
;			cld
;			rep		stosd
;			pop		eax
			push	dword buf
			push	eax
			call	_tostring
			add		esp, 8
			push	dword 1024
			push	dword buf
			call	_puttoken
			add		esp, 8
			
	.else:
		cmp		ebx, tt_alpha
		jne		.endif

			push	eax
			push	dword buf
			call	_store	
			add		esp, 8

			push	dword buf
			push	eax
			call	_tostring
			pop		eax
			add		esp, 4

			push	eax
			push	dword 1024
			push	dword buf
			call	_puttoken
			add		esp, 8
			pop		eax

			push	dword 1024
			push	eax
			call	_puttoken
			add		esp, 8
	
	.endif:

		push	dword 100
		push	ebx
		call	_puttoken
		add		esp, 8

		call	_flush

		push	esp
		push	dword 1024
		push	dword buf
		call	_gettoken
		add		esp, 12
		jmp		.loop
.endloop:
	
	add		esp, 4
	pop		ebx
	pop		esi
	leave
	ret

_test5:
	enter	0, 0
	call	_init
	mov		ebx, dword nil
	mov		edx, [ebx]
	mov		ecx, 1
.loop1:
		mov		eax, ecx
		push	ecx
		push	edx
		call	_number
		pop		edx
		pop		ecx
		call	_cons
		mov		edx, eax
		inc		ecx
		cmp		ecx, 10
		jle		.loop1
	sub		esp, 12
	mov		ebx, esp
.loop2:
		cmp		edx, [nil]
		je		.endloop2
		push	edx
		mov		eax, edx
		call	_car
		call	_ivalue
		push	ebx	
		push	eax
		call	_tostring
		add		esp, 8
		push	dword 12
		push	ebx
		call	_puttoken
		add		esp, 8
		call	_flush
		pop		eax
		call	_cdr
		mov		edx, eax
		jmp		.loop2
.endloop2:
	add		esp, 12
	leave
	ret
	
_test6:
	enter	0, 0
	call	_init
	mov		ebx, dword nil
	mov		edx, [ebx]
	mov		ecx, 1
.loop:
		mov		eax, ecx
		push	ecx
		push	edx
		call	_number
		pop		edx
		pop		ecx
		call	_cons
		mov		edx, eax
		inc		ecx
		cmp		ecx, 10
		jle		.loop
	push	edx
	call	_putexp
	add		esp, 4
	call	_flush
	leave
	ret
	
