segment .bss
	global cons

free		resb	2048
cons		resd	16384


segment .text
	global _cons_alloc
	global _cons_free
	global _cons_init

_cons_init:
	enter	0, 0
	mov		eax, 0xffffffff
	mov		edi, dword free
	mov		ecx, 512
	cld
	rep		stosd
	leave
	ret


_cons_free:
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
	bts		[free + eax*4], edx

	leave
	ret

_cons_alloc:
	enter	0, 0

	; Loop through the free list to find an entry that has
	; a bit that is set (i.e., the corresponding cons cell
	; is free).
	mov		eax, 0
	mov		edi, dword free 
	mov		ecx, 512
	cld
	repz	scasd

	; If ZF is set (i.e., the last comparison in the above
	; loop was satisfied (EAX = 0), then all space in the
	; cons cell array has been exhausted.
	jz		.out_of_space

	sub		edi, 4
	
	; EDI holds offset to a 32-bit field with at least
	; one bit set (i.e., at least one field is free).

	; Find a bit that's set
	bsf		eax, [edi]		; EAX <-- free bit in [EDI] 

	; Mark the cons cell as allocated
	btr		[edi], eax

	; Return pointer to cons cell:
	;   EDI: offset into free array of 32-bit integers
	;   EAX: bit index into integer from free (each bit
	;        represents the free state of a cons cell).
	;   ==> The index of the cons cell is EDI*8 + EDX
	;   ==> The address of the cons cell is cons + EDI*32 + EDX*4
	; 

	shl		edi, 5
	lea		eax, [cons + edi + eax*4]
	
;	mov		eax, ecx
;	shl		eax, 5
;	add		eax, edx

	leave
	ret	

.out_of_space:
	; No more space left (raise error)
	mov		eax, 0 
	
	leave
	ret

