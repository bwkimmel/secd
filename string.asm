%define STORE_SIZE 65536
%define HASH_SIZE 16381

segment .bss
hash		resd		HASH_SIZE
store		resb		STORE_SIZE
storeptr	resd		1
storeend	resd		1

segment .text
	global	_init_strings

_init_strings:
	enter	0, 0
	push	edi
	mov		eax, 0
	mov		ecx, HASH_SIZE
	mov		edi, dword hash
	cld
	rep		stosd
	mov		eax, dword store
	mov		[storeptr], eax
	add		eax, STORE_SIZE
	mov		[storeend], eax
	pop		edi
	leave
	ret

_hash:
	enter	0, 0
	push	esi
	mov		esi, [ebp + 8]
	mov		ecx, [ebp + 12]
	mov		eax, 0
.loop:
		mov		edx, 0
		mov		dl, byte [esi]
		inc		esi
		sub		edx, eax
		shl		eax, 6
		add		edx, eax
		shl		eax, 10
		add		eax, edx
		loop	.loop
.done:
	pop		esi
	leave
	ret

_store:
	enter	0, 0
	push	esi
	push	edi

	mov		esi, [ebp + 8]
	mov		ecx, [ebp + 12]

	push	ecx
	push	esi
	call	_hash
	add		esp, 8

	mov		ecx, dword HASH_SIZE
	mov		edx, 0
	div		ecx
.probe_loop:
		mov		eax, [dword hash + edx * 4]
		cmp		eax, 0
		je		.probe_endloop
		; TODO: check if the string at this location in the
		; hash table matches the string we are trying to
		; store.  If so, return that string
		inc		edx
		cmp		edx, HASH_SIZE
		jne		.endif
			mov		edx, 0
	.endif:
		loop	.probe_loop
		jmp		.full
.probe_endloop:

	mov		ecx, [ebp + 12]

	mov		edi, dword storeptr
	mov		eax, edi
	add		eax, ecx
	cmp		eax, dword storeend
	jge		.full

	mov		[dword hash + edx * 4], edi	

	cld
	rep		stosb
	mov		byte [edi], 0
	inc		edi
	xchg	edi, [storeptr]
	mov		eax, edi
.done:
	pop		edi
	pop		esi
	leave
	ret
.full:
	mov		eax, 0
	jmp		.done

