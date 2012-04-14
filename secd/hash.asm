; ==============================================================================
; Hash table implementation                                           UNFINISHED
; ==============================================================================
;

segment .data
next		dd		0				; where to allocate next chunk
active_heap	dd		0				; pointer to active half of heap

segment .bss
align 8
heap1		resb	HEAP_SIZE		; first half of heap
heap2		resb	HEAP_SIZE		; second half of heap

; ==============================================================================
; Exported functions
;
segment .text
global		_hash_req, _hash_init, _hash_put, _hash_get	

_hash_req:
	enter	0, 0

	mov		eax, [ebp + 8]
	shl		eax, 2
	add		eax, 8

	leave
	ret

_hash_init:
	enter	0, 0

	mov		edi, [ebp + 8]			; EDI = pointer to hash table
	mov		eax, [ebp + 12]			; EAX = size of hash table (incl. cellar)
	mov		edx, [ebp + 16]			; EDX = size of addr space of hash function

	mov		[edi], eax
	mov		[edi + 4], edx

	leave
	ret

; ------------------------------------------------------------------------------
; 
; ------------------------------------------------------------------------------
_hash_put:
	enter	0, 0

	mov		edi, [ebp + 8]
	mov		eax, [ebp + 12]
	mov		edx, 0

	mov		ebx, [edi + 4]
	div		ebx

	mov		eax, [edi + edx * 4]
	cmp		eax, 0
	jne		.else
		mov		eax, [ebp + 16]
		shl		eax, 16
		mov		[edi + edx * 4], eax
		jmp		.endif
	.full:
		mov		eax, -1
		jmp		.endif
	.else:
		mov		ebx, [edi]
		.loop_findslot:
			dec		ebx
			js		.full
			cmp		[edi + ebx * 4], 0
			jne		.loop_findslot
		.loop_tail:
			mov		eax, [edi + edx * 4]
			test	eax, 0xffff
			jz		.endloop_tail
			mov		dx, ax
			jmp		.loop_tail
		.endloop_tail:
		or		ax, bx
		mov		[edi + edx * 4], eax
		mov		eax, [ebp + 16]
		shl		eax, 16
		mov		[edi + ebx * 4], eax
	.endif:

	mov		eax, 0

	leave
	ret

_hash_get:
	enter	0, 0

	mov		edi, [ebp + 8]
	mov		eax, [ebp + 12]
	mov		edx, 0

	mov		ebx, [edi + 4]
	div		ebx

	mov		eax, [edi + edx * 4]
	cmp		eax, 0
	je		.endif

	.loop:
		mov		ebx, eax
		shr		ebx, 16

		; check to see if ebx refers to correct cell, if so jump to .found

		and		eax, 0xffff
		jz		.endif

		mov		edx, eax
		mov		eax, [edi + edx * 4]
		jmp		.loop

	.found:
		mov		eax, edx

	.endif:

	leave
	ret

