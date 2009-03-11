%define INBUF_SIZE	80
%define OUTBUF_SIZE	80

section .data
tt_eof		db		"ENDFILE", 0
tt_num		db		"NUMERIC", 0
tt_alpha	db		"ALPHANUMERIC", 0
tt_delim	db		"DELIMITER", 0
eof			dd		0

section .bss
inbuf		resb	INBUF_SIZE
outbuf		resb	OUTBUF_SIZE
inbufend	resd	1
inbufptr	resd	1
outbufptr	resd	1
char		resd	1

section .text
	global _putchar, _length, _puttoken, _tostring, _tointeger, \
		_getchar, _gettoken, _isdigit, _isletter, _getline, _scan, _isws

_isws:
	enter	0, 0
	mov		eax, [ebp + 8]
	cmp		eax, '\n'
	je		.true
	cmp		eax, '\r'
	je		.true
	cmp		eax, '\t'
	je		.true
	cmp		eax, ' '
	je		.true
	cmp		eax, 0
	je		.true
	mov		eax, 0
	leave
	ret
.true:
	mov		eax, 1
	leave
	ret

_getline:
	enter	0, 0
	push	ebx
	push	edi
	sub		esp, 4
	mov		ebx, esp
	mov		edi, [ebp + 8]		; destination buffer
	mov		ecx, [ebp + 12]		; maximum length
.lineloop:
		push	dword 0			; offset
		push	dword 1			; number of bytes
		push	ebx				; buffer
		push	dword stdin		; file descriptor
		sys.read	
		add		esp, 16
		cmp		eax, 0
		jl		.error
		je		.eof
		mov		dl, byte [ebx]
		cmp		dl, '\n'
		je		.done
		cmp		dl, '\r'
		je		.lineloop
		cmp		dl, '\0'
		je		.done
		mov		byte [edi], dl
		inc		edi	
		loop	.lineloop
.eof:
	mov		[eof], 1
.done:
	mov		eax, edi
	sub		eax, [ebp + 8]
	add		esp, 4
	pop		edi
	pop		ebx
	leave
	ret
.error:
	mov		eax, -1
	add		esp, 4
	pop		edi
	pop		ebx
	leave
	ret

_getchar:
	enter	0, 0
	mov		ecx, [inbufptr]
	cmp		ecx, [inbufend]
	jle		.endif
		; getline
		push	dword OUTBUF_SIZE
		push	dword inbuf
		call	_getline
		add		esp, 8
		mov		ecx, 0
		; FIXME: check for EAX < 0 (error)
		;cmp		eax, 0
		;jl		.error
.endif:
	mov		eax, 0
	mov		al, byte [inbuf + ecx]
	mov		dword [char], eax
	inc		ecx
	mov		[inbufptr], ecx
	leave
	ret	

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
	cmp		eax, 0
	jne		.digit
	cmp		ebx, '-'
	je		.digit

	call	_isletter
	cmp		eax, 0
	jne		.letter

.delimiter:
	mov		[ebp + 16], dword tt_delim
	mov		byte [edi], bl 
	inc		edi
	call	_getchar	
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
	mov		[ebp + 16], dword tt_num
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
	mov		[ebp + 16], dword tt_alpha
	jmp		.done
	
.eof:
	mov		[ebp + 16], dword tt_eof

.done:
	mov		eax, edi
	sub		eax, [ebp + 8]
	pop		edi
	pop		ebx
	leave
	ret

_scan:
	enter	0, 0
	push	[ebp + 16]
	push	[ebp + 12]
	push	[ebp + 8]
	call	_gettoken
	mov		edx, [esp + 8]
	add		esp, 12
	cmp		edx, tt_eof
	jne		.endif
		push	edi
		mov		edi, [ebp + 8]
		mov		byte [edi], ')'
		mov		eax, 1
.endif:
	mov		[ebp + 16], edx
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
	cmp		eax, 'A'
	jl		.false
	cmp		eax, 'z'
	jg		.false
	cmp		eax, 'Z'
	jle		.true
	cmp		eax, 'a'
	jge		.true
.false:
	mov		eax, 0
	leave
	ret
.true:
	mov		eax, 1
	leave
	ret	

_puttoken:
	enter	0, 0
	mov		edx, [ebp + 8]
	mov		ecx, [ebp + 12]
	cmp		ecx, 0
	jle		.done
.loop:
		mov		eax, 0
		mov		al, byte [edx]
		cmp		al, 0
		jz		.done
		push	eax
		call	_putchar
		add		esp, 4
		dec		ecx
		jnz		.loop
.done:
	leave
	ret

_putchar:
	enter	0, 0
	mov		eax, [ebp + 8]
	mov		ecx, [outbufptr]
	cmp		ecx, OUTBUF_SIZE
	jb		.endif
		push	dword outbufptr
		push	dword outbuf
		push	dword stdout
		sys.write
		mov		ecx, 0
.endif:
	mov		byte [outbuf + ecx], al
	inc		ecx
	mov		[outbufptr], ecx
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
		cmp		dl, '9'
		ja		.done
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
.endif
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
	dec		esi
	mov		byte [esi], '0'
	mov		ecx, 1

.loop:
		mov		edx, 0			; Sign extend abs(EAX) into EDX for div
		div		ebx
		add		edx, '0'
		dec		esi
		mov		byte [esi], dl
		inc		ecx
		cmp		eax, 0
		jne		.loop

.done:
	cld
	rep		movsb
	add		esp, 12
	pop		edi
	pop		esi
	pop		ebx
	leave
	ret

.zero:
	mov		[edi], byte '0'
	mov		[edi + 1], byte 0
	jmp		.done	

.negative:
	neg		eax
	mov		[edi], byte '-'
	inc		edi
	jmp		.start

_length:
	enter	0, 0
	push	esi
	mov		edx, [ebp + 8]
	mov		esi, edx
	mov		eax, 0
	cld
	rep		scasb
	dec		esi
	mov		eax, esi
	sub		eax, edx
	pop		esi
	leave
	ret	

