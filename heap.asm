%define HEAP_SIZE (1*1024*1024)

segment .data
next		dd		0
active_heap	dd		0

segment .bss
align 8
heap1		resb	HEAP_SIZE
heap2		resb	HEAP_SIZE

segment .text
global		_heap_alloc, _heap_forward, _heap_mark, _heap_sweep, \
			_heap_item_length

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

_heap_mark:
	or		[eax - 4], dword 0x80000000
	ret

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

_heap_forward:
	mov		eax, dword [eax - 4]
	ret

_heap_item_length:
	mov		eax, dword [eax - 4]
	and		eax, 0x7fffffff
	ret
	
