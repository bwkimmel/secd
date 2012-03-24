%include 'system.inc'
%include 'secd.inc'

%define INBUF_SIZE		1024
%define OUTBUF_SIZE		80
%define MAX_TOKEN_SIZE	1024

section .data
	global tt_eof, tt_num, tt_alpha, tt_delim
	extern nil

tt_eof		db		"ENDFILE", 0
tt_num		db		"NUMERIC", 0
tt_alpha	db		"ALPHANUMERIC", 0
tt_delim	db		"DELIMITER", 0
eof			dd		0
outbufind	dd		0
open_paren	db		"("
close_paren	db		")"
dot			db		"."
ellipsis	db		"..."
ellips_len	equ		$ - ellipsis

section .bss
inbuf		resb	INBUF_SIZE
outbuf		resb	OUTBUF_SIZE
inbufptr	resd	1
inbufend	resd	1
char		resd	1
token		resb	MAX_TOKEN_SIZE
type		resd	1
visited		resb	65536

section .text
	global _putchar, _length, _puttoken, _tostring, _tointeger, \
		_getchar, _gettoken, _isdigit, _isletter, _scan, _isws, \
		_flush, _putexp, _getexp, _getexplist
	extern _flags, _ivalue, _svalue, _car, _cdr, _store, _cons, _symbol, \
		_number

_getexp:
	enter	0, 0
	cmp		[token], byte '('
	jne		.elseif
	cmp		[token + 1], byte 0
	jne		.elseif
		call	_scan
		call	_getexplist
		jmp		.endif

.elseif:
	cmp		[type], dword tt_num
	jne		.else
		push	dword MAX_TOKEN_SIZE
		push	dword token
		call	_tointeger
		add		esp, 8
		call	_number
		jmp		.endif

.else:
		push	dword token
		call	_length
		add		esp, 4
		push	eax
		push	dword token
		call	_store
		add		esp, 8
		call	_symbol
	
.endif:
	push	eax
	call	_scan
	pop		eax
	leave
	ret

_getexplist:
	enter	0, 0
	push	ebx
	call	_getexp
	mov		ebx, eax
	cmp		[token], byte '.'
	jne		.elseif
	cmp		[token + 1], byte 0
	jne		.else
		call	_scan
		call	_getexp
		jmp		.endif		

.elseif:
	cmp		[token], byte ')'
	jne		.else
	cmp		[token + 1], byte 0
	jne		.else
		mov		eax, dword 0
		jmp		.endif

.else:
	call	_getexplist

.endif:
	mov		edx, eax
	mov		eax, ebx
	call	_cons
	pop		ebx
	leave
	ret

_putexp:
	enter	0, 0
	push	ebx
	mov		ebx, [ebp + 8]
	cmp		[visited + ebx], byte 0
	je		.not_visited
		push	dword ellips_len
		push	dword ellipsis
		call	_puttoken
		add		esp, 8
		pop		ebx
		leave
		ret
.not_visited:
	mov		[visited + ebx], byte 1
	mov		eax, ebx
	call	_flags
	test	eax, SECD_ATOM
	jz		.putcons
	and		eax, SECD_TYPEMASK
	cmp		eax, SECD_SYMBOL
	je		.putsym
.putint:
	mov		eax, ebx
	call	_ivalue
	sub		esp, 12
	mov		ebx, esp
	push	ebx
	push	eax
	call	_tostring
	add		esp, 8
	push	dword 12
	push	ebx
	call	_puttoken
	add		esp, 20 
	jmp		.done
.putsym:
	mov		eax, ebx
	call	_ivalue
	mov		ebx, eax
	push	eax
	call	_length
	add		esp, 4
	push	eax
	push	ebx
	call	_puttoken
	add		esp, 8
	jmp		.done
.putcons:
	push	dword 1
	push	dword open_paren
	call	_puttoken
	add		esp, 8	
.consloop:
		mov		eax, ebx
		call	_car
		push	eax		
		call	_putexp
		add		esp, 4
		mov		eax, ebx
		call	_cdr
		mov		ebx, eax
		call	_flags
		and		eax, SECD_TYPEMASK
		cmp		eax, SECD_CONS
		je		.consloop	
	cmp		eax, SECD_SYMBOL
	jne		.cons_dot
	mov		edx, ebx
	mov		eax, dword 0
	call	_ivalue
	xchg	eax, ebx
	call	_ivalue
	cmp		eax, ebx	
	je		.cons_end
	mov		ebx, edx
.cons_dot:
	push	dword 1
	push	dword dot
	call	_puttoken
	add		esp, 8
	push	ebx
	call	_putexp
	add		esp, 4
.cons_end:
	push	dword 1
	push	dword close_paren
	call	_puttoken
	add		esp, 8
.done:
	mov		ebx, [ebp + 8]
	mov		[visited + ebx], byte 0
	pop		ebx
	leave
	ret

_isws:
	enter	0, 0
	mov		eax, [ebp + 8]
	cmp		eax, 13		; \n
	je		.true
	cmp		eax, 10		; \r 
	je		.true
	cmp		eax, 9		; \t
	je		.true
	cmp		eax, 32		; space 
	je		.true
	cmp		eax, 0		; \0
	je		.true
	mov		eax, 0
	leave
	ret
.true:
	mov		eax, 1
	leave
	ret

_getchar:
	enter	0, 0
	push	esi
	mov		esi, [inbufptr]
	cmp		esi, [inbufend]
	jl		.endif
		sys.read stdin, inbuf, INBUF_SIZE
		cmp		eax, 0
		je		.eof
		jl		.error
		mov		esi, dword inbuf
		add		eax, esi
		mov		[inbufend], eax
.endif:
	mov		eax, 0
	mov		al, byte [esi]
	mov		[char], eax
	inc		esi
	mov		[inbufptr], esi
.done:
	pop		esi
	leave
	ret
.error:
.eof:
	mov		eax, -1
	mov		[eof], dword 1
	jmp		.done

_gettoken:
	enter	0, 0
	push	ebx
	push	edi
	mov		edi, [ebp + 8]
	mov		ecx, [ebp + 12]
.loop:
		cmp		dword [eof], 0
		jne		.eof
		push	dword [char]
		call	_isws
		add		esp, 4
		cmp		eax, 0
		je		.endloop
		call	_getchar
		jmp		.loop
.endloop:
	mov		ebx, dword [char]

	push	ebx
	call	_isdigit
	add		esp, 4

	cmp		eax, 0
	jne		.digit
	cmp		ebx, '-'
	je		.digit

	push	ebx
	call	_isletter
	add		esp, 4
	cmp		eax, 0
	jne		.letter

.delimiter:
	mov		edx, [ebp + 16]
	mov		[edx], dword tt_delim
	mov		byte [edi], bl 
	inc		edi
	call	_getchar	
	jmp		.done
	
.eof:
	mov		edx, [ebp + 16]
	mov		[edx], dword tt_eof
	jmp		.done

.digit:
	mov		byte [edi], bl
	inc		edi
	call	_getchar
	mov		ebx, dword [char]
.digit_loop:
		push	ebx
		call	_isdigit
		add		esp, 4
		cmp		eax, 0
		je		.digit_endloop
		mov		byte [edi], bl
		inc		edi
		call	_getchar
		mov		ebx, dword [char]
		jmp		.digit_loop
.digit_endloop:
	mov		edx, [ebp + 16]
	mov		[edx], dword tt_num
	jmp		.done

.letter:
	mov		byte [edi], bl
	inc		edi
	call	_getchar
	mov		ebx, dword [char]
.alpha_loop:
		push	ebx
		call	_isletter
		add		esp, 4
		cmp		eax, 0
		jne		.alpha_continue
		push	ebx
		call	_isdigit
		add		esp, 4
		cmp		eax, 0
		je		.alpha_endloop
.alpha_continue:
		mov		byte [edi], bl
		inc		edi
		call	_getchar
		mov		ebx, dword [char]
		jmp		.alpha_loop
.alpha_endloop:
	mov		edx, [ebp + 16]
	mov		[edx], dword tt_alpha

.done:
	mov		eax, edi
	sub		eax, [ebp + 8]
	mov		[edi], byte 0
	pop		edi
	pop		ebx
	leave
	ret

_scan:
	enter	0, 0
	push	dword type
	push	dword MAX_TOKEN_SIZE
	push	dword token
	call	_gettoken
	add		esp, 12
	cmp		[type], dword tt_eof
	jne		.endif
		mov		[type], dword tt_delim
		mov		[token], byte ')'
		mov		[token + 1], byte 0
.endif:
	leave
	ret

_isdigit:
	enter	0, 0
	mov		eax, [ebp + 8]
	cmp		eax, '0'
	jl		.else
	cmp		eax, '9'
	jg		.else
		mov		eax, 1
		leave
		ret
.else:
		mov		eax, 0
		leave
		ret

_isletter:
	enter	0, 0
	mov		eax, [ebp + 8]
	push	eax
	call	_isws
	add		esp, 4
	cmp		eax, 0
	jne		.false
	mov		eax, [ebp + 8]
	push	eax
	call	_isdigit
	add		esp, 4
	cmp		eax, 0
	jne		.false
	mov		eax, [ebp + 8]
	cmp		eax, '('
	je		.false
	cmp		eax, ')'
	je		.false
	cmp		eax, '.'
	je		.false
	cmp		eax, '-'
	je		.false
.true:
	mov		eax, 1
	leave
	ret
.false:
	mov		eax, 0
	leave
	ret	

_puttoken:
	enter	0, 0
	push	ebx
	push	esi
	mov		esi, [ebp + 8]
	mov		ebx, [ebp + 12]
	cmp		ebx, 0
	jle		.done
.loop:
		mov		eax, 0
		mov		al, byte [esi]
		cmp		al, 0
		je		.done
		push	ebx
		push	esi
		push	eax
		call	_putchar
		add		esp, 4
		pop		esi
		pop		ebx
		inc		esi
		dec		ebx
		jnz		.loop
.done:
	push	dword ' '
	call	_putchar
	add		esp, 4
	pop		esi
	pop		ebx
	leave
	ret

_flush:
	enter	0, 0
	sys.write stdout, outbuf, [outbufind]
	mov		dword [outbufind], 0
	leave
	ret

_putchar:
	enter	0, 0
	mov		ecx, [outbufind]
	cmp		ecx, OUTBUF_SIZE
	jb		.endif
		sys.write stdout, outbuf, OUTBUF_SIZE
		mov		ecx, 0
.endif:
	mov		eax, [ebp + 8]
	mov		byte [outbuf + ecx], al
	inc		ecx
	mov		[outbufind], ecx
	leave
	ret

_tointeger:
	enter	0, 0
	push	esi
	push	ebx
	mov		eax, 0
	mov		esi, [ebp + 8]		; String to convert to integer
	mov		ecx, [ebp + 12]		; Maximum length
	mov		edx, 0
	cmp		byte [esi], '-'
	je		.advance
.loop:
		mov		dl, byte [esi]
		sub		dl, '0'
		jo		.done
		jc		.done
		cmp		dl, '9'
		jg		.done
		mov		ebx, eax
		shl		eax, 2
		add		eax, ebx
		shl		eax, 1			; EAX <-- EAX * 10
		add		eax, edx		; EAX <-- EAX + digit
.advance:
		inc		esi
		loop	.loop
.done:
	mov		esi, [ebp + 8]
	cmp		byte [esi], '-'
	jne		.endif
		neg		eax
.endif:
	pop		ebx
	pop		esi
	leave
	ret

_tostring:
	enter	0, 0
	push	ebx
	push	esi
	push	edi

	mov		eax, [ebp + 8]		; Integer to convert
	mov		edi, [ebp + 12]		; Buffer to write to

	cmp		eax, 0
	je		.zero
	jl		.negative

.start:
	mov		ebx, 10				; We are going to be dividing by 10
	mov		esi, esp
	sub		esp, 12
	mov		ecx, 0

.loop:
		mov		edx, 0			; Sign extend abs(EAX) into EDX for div
		div		ebx
		add		edx, '0'
		dec		esi
		mov		byte [esi], dl
		inc		ecx
		cmp		eax, 0
		jne		.loop

	cld
	rep		movsb
	add		esp, 12
.done:
	mov		[edi], byte 0
	pop		edi
	pop		esi
	pop		ebx
	leave
	ret

.zero:
	mov		[edi], byte '0'
	inc		edi
	jmp		.done	

.negative:
	neg		eax
	mov		[edi], byte '-'
	inc		edi
	jmp		.start

_length:
	enter	0, 0
	push	edi
	mov		edx, [ebp + 8]
	mov		edi, edx
	mov		ecx, -1
	mov		eax, 0
	cld
.scan:
	scasb
	jnz		.scan
	dec		edi
	mov		eax, edi
	sub		eax, edx
	pop		edi
	leave
	ret	

