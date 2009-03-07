segment .bss

free		resb	2048
cons		resd	16384


segment .text
	global	cons_alloc
	global	cons_free

cons_free:
	enter	0, 0

	; EAX contains a pointer to a cons cell.
	; We want to find the associated index into
	; the cons array.
	sub		eax, dword cons		; EAX <-- EAX - &cons
	shr		eax, 2				; EAX <-- EAX / 4

	mov		edx, eax
	shr		eax, 5				; EAX <-- index into free
	and		edx, 0x1f			; EDX <-- bit to reset

	; Mark the cons cell as free
	btr		[free + eax*4], edx

	leave
	ret

cons_alloc:
	enter	0, 0

	; Loop through the free list to find an entry that has
	; a bit that is not set (i.e., the corresponding cons
	; cell is free).
	push	ebx
	mov		ebx, dword free 
	
	mov		ecx, 512
.search:
		mov		eax, [ebx + (ecx-1)*4]
		cmp		eax, 0xffffffff
		loope	.search
	
; End of loop

	pop		ebx

	; If ZF is set (i.e., the last comparison in the above
	; loop was satisfied (EAX = 0xFFFFFFFF), then all space
	; in the cons cell array has been exhausted.
	je		.out_of_space
	
	; ECX holds index to a 32-bit field with at least
	; one bit NOT set (i.e., at least one field is free).

	; Find a bit that's not set
	mov		edx, eax
	not		edx
	bsf		edx, edx		; EDX <-- free bit in EAX

	; Mark the cons cell as allocated
	bts		eax, edx
	mov		[free + ecx*4], eax

	; Return pointer to cons cell:
	;   ECX: index into free array of 32-bit integers
	;   EDX: bit index into integer from free (each bit
	;        represents the free state of a cons cell).
	;   ==> The index of the cons cell is ECX*32 + EDX
	;   ==> The address of the cons cell is cons + ECX*128 + EDX*4
	; 
	shl		ecx, $7			; ECX <-- ECX * 128
	lea		eax, [cons + ecx + edx*4]

	leave
	ret	

.out_of_space:
	; No more space left (raise error)
	mov		eax, 0
	
	leave
	ret

