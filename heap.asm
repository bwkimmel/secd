; ==============================================================================
; Heap implementation                                                 UNFINISHED
;
; This implements dynamic allocation of variable-length chunks of memory.  To
; perform garbage collection, the heap is divided into two halves.  Allocation
; takes place in a linear fashion on one half.  When that half becomes full,
; a we perform a garbage collection cycle.  This consists of marking all the
; chunks which are still in use (which is the responsibility of the client of
; the heap), and then copying the marked objects to the other half of the heap
; (thus compacting the heap in the process).  Forwarding markers must be left in
; place of the old objects so that references to those old objects know where
; to find the new object.
; ==============================================================================
;
%%define HEAP_SIZE (1*1024*1024)

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
global		_heap_alloc, _heap_forward, _heap_mark, _heap_sweep, \
			_heap_item_length

; ------------------------------------------------------------------------------
; Allocate a new chunk
; EXPECTS eax = size of chunk to allocate
; RETURNS pointer to new chunk, or 0 if the heap is full
; ------------------------------------------------------------------------------
_heap_alloc:
	push	ebx
	mov		ecx, eax

	; check if heap is initialized
	mov		eax, [next]
	cmp		eax, dword 0
	jne		.endif_init
		mov		eax, dword heap1
		mov		[active_heap], dword heap1
.endif_init:

	; align on dword boundary
	mov		edx, ecx
	add		edx, 3
	and		edx, 0xfffffffc

	; check if there is enough space remaining
	lea		edx, [eax + edx + 4]
	mov		ebx, [active_heap]
	add		ebx, dword HEAP_SIZE
	cmp		edx, ebx
	jg		.full
.endif_full:
	mov		[eax], ecx
	mov		[next], edx
	add		eax, 4
	pop		ebx
	ret
.full:
	mov		eax, 0
	pop		ebx
	ret

; ------------------------------------------------------------------------------
; Marks a chunk
; EXPECTS eax = pointer to chunk
; ------------------------------------------------------------------------------
_heap_mark:
	or		[eax - 4], dword 0x80000000
	ret

; ------------------------------------------------------------------------------
; Compacts heap by moving all marked chunks to the other half.
; ------------------------------------------------------------------------------
_heap_sweep:
	push	ebx
	push	esi
	push	edi
	
	cld
	mov		ebx, dword [active_heap]
	mov		esi, ebx
	add		ebx, dword HEAP_SIZE

	cmp		esi, dword heap1
	jne		.else
		mov		edi, dword heap2
		jmp		.endif
.else:
		mov		edi, dword heap1
.endif:
	mov		dword [active_heap], edi

.loop:
		mov		ecx, dword [esi]
		test	ecx, dword 0x80000000
		jz		.unmarked
			and		ecx, dword 0x7fffffff
			mov		dword [edi], ecx
			add		edi, 4
			mov		dword [esi], edi
			add		esi, 4
			add		ecx, 3
			and		ecx, 0xfffffffc
			shr		ecx, 2
		.loop_copy:
			rep		movsd
			jcxz	.endloop
			loop	.loop_copy
	
	.unmarked:
		add		esi, 4
		add		esi, ecx
.endloop:
		cmp		esi, dword HEAP_SIZE
		jle		.loop

	mov		dword [next], edi

	pop		edi
	pop		esi
	pop		ebx
	ret

; ------------------------------------------------------------------------------
; Follows chunk forwarding pointer
; EXPECTS eax = pointer to forwarded chunk
; RETURNS pointer to new location of chunk
; ------------------------------------------------------------------------------
_heap_forward:
	mov		eax, dword [eax - 4]
	ret

; ------------------------------------------------------------------------------
; Gets the size of a chunk
; EXPECTS eax = pointer to chunk
; RETURNS size of chunk
; ------------------------------------------------------------------------------
_heap_item_length:
	mov		eax, dword [eax - 4]
	and		eax, 0x7fffffff
	ret
	
