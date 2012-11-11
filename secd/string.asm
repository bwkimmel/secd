; ==============================================================================
; String-store implementation
;
; The string-store represents a set of strings used for symbols.  It ensures
; that only one copy of any given string is ever added, so that equal strings in
; the input evaluate to the same symbol.
; ==============================================================================
;
%define STORE_SIZE 65536            ; Amount of memory for string storage
%define HASH_SIZE 16381             ; Size of hash table (should be a prime number)

segment .bss
hash        resd        HASH_SIZE   ; Hash table
data        resb        STORE_SIZE  ; String storage block
dataptr     resd        1           ; Location to store next string
dataend     resd        1           ; End of string stoage block


; ==============================================================================
; Exported functions
;
segment .text
    global  _init_strings, _store

; ------------------------------------------------------------------------------
; Initializes the string store
; ------------------------------------------------------------------------------
_init_strings:
    enter   0, 0
    push    edi
    mov     eax, 0
    mov     ecx, HASH_SIZE
    mov     edi, dword hash
    cld
    rep     stosd
    mov     eax, dword data
    mov     [dataptr], eax
    add     eax, STORE_SIZE
    mov     [dataend], eax
    pop     edi
    leave
    ret

; ------------------------------------------------------------------------------
; Addes a new string to the string store
; USAGE: _store(<string>, <length>)
; <string> = the string to store
; <length> = the length of the string
; RETURNS the pointer to the string in the string store, or 0 if the string
;         store is full.
; ------------------------------------------------------------------------------
_store:
    enter   0, 0
    push    esi
    push    edi

    mov     esi, [ebp + 8]          ; ESI <-- <string>
    mov     ecx, [ebp + 12]         ; ECX <-- <length>

    push    ecx
    push    esi
    call    _hash                   ; compute hash code
    add     esp, 8

    mov     ecx, dword HASH_SIZE
    mov     edx, 0
    div     ecx
.probe_loop:                        ; scan for empty cell to store string in
        mov     edi, [dword hash + edx * 4]
        cmp     edi, 0
        je      .probe_endloop

        push    ecx
        mov     ecx, [ebp + 12]
    .compare_loop:
            cmpsb
            jne     .compare_endloop
            cmp     byte [edi], 0   
            loopne  .compare_loop
        cmp     byte [edi], 0
        jne     .compare_endloop
        pop     ecx
        mov     eax, [dword hash + edx * 4]
        jmp     .done

    .compare_endloop:
        pop     ecx

        mov     esi, [ebp + 8]
        
        ; TODO: check if the string at this location in the
        ; hash table matches the string we are trying to
        ; store.  If so, return that string
        inc     edx
        cmp     edx, dword HASH_SIZE
        jne     .endif
            mov     edx, 0
    .endif:
        loop    .probe_loop
        jmp     .full
.probe_endloop:

    mov     ecx, [ebp + 12]

    mov     edi, [dataptr]          ; check if write will go past end of string
    mov     eax, edi                ; store.
    add     eax, ecx
    cmp     eax, [dataend]
    jge     .full

    mov     [dword hash + edx * 4], edi 

    cld
    rep     movsb                   ; write string to string store
    mov     byte [edi], 0
    inc     edi
    xchg    edi, [dataptr]          ; update ptr to next string
    mov     eax, edi
.done:
    pop     edi
    pop     esi
    leave
    ret
.full:
    mov     eax, 0
    jmp     .done


; ==============================================================================
; Internal functions
;

; ------------------------------------------------------------------------------
; Computes the hash code for a string
; USAGE: _hash(<string>, <length>)
; <string> = the string to compute the hash code for
; <length> = the length of the string
; RETURNS the hash code
; ------------------------------------------------------------------------------
_hash:
    enter   0, 0
    push    esi
    mov     esi, [ebp + 8]          ; ESI <-- <string>
    mov     ecx, [ebp + 12]         ; ECX <-- <length>
    mov     eax, 0
.loop:
        mov     edx, 0
        mov     dl, byte [esi]
        inc     esi
        sub     edx, eax
        shl     eax, 6
        add     edx, eax
        shl     eax, 10
        add     eax, edx
        loop    .loop
.done:
    pop     esi
    leave
    ret

