; 1111 11
; 5432 1098 7654 3210
; -------------------
; dddd dddd dddd dd10 16-bit offset into cons array 
; sddd dddd dddd dd01 signed 14-bit integer
; dddd dddd dddd 0011 12-bit index into atom table
; dddd dddd dddd 0111 12-bit index into double table
; cccc cccc 1000 1111 8-bit ASCII character
; 0000 0000 0000 0000 #f
; 1111 1111 1111 1111 #t
; 1111 1111 1111 1100 #n 
; 1000 0000 0000 0000 '() 

%define ATOM_MASK			0x000f
%define ATOM_FLAG			0x0003
%define	ATOM_MASK_BITS		4

%define CONS_MASK			0x0003
%define CONS_FLAG			0x0002
%define CONS_MASK_BITS		2

%define INT_MASK			0x0003
%define INT_FLAG			0x0001
%define INT_MASK_BITS		2

%define CHAR_MASK			0x00ff
%define CHAR_FLAG			0x008f
%define CHAR_MASK_BITS		8

%define DOUBLE_MASK			0x000f
%define DOUBLE_FLAG			0x0007
%define DOUBLE_MASK_BITS	4

%define TRUE		0xffff
%define FALSE		0x0000
%define DNP			0xfffc
%define NULL		0x8000
%define INT_ZERO	INT_FLAG
%define INT_ONE		INT_FLAG | (1 << INT_MASK_BITS)

%macro mask_atom 1
	shl		%1, ATOM_MASK_BITS 
	or		%1, ATOM_FLAG
%endmacro

%macro unmask_atom 1
	shr		%1, ATOM_MASK_BITS 
%endmacro

%macro mask_int 1
	shl		%1, INT_MASK_BITS 
	or		%1, INT_FLAG
%endmacro

%macro unmask_int 1
	shr		%1, INT_MASK_BITS
%endmacro

%macro mask_char 1
	shl		%1, CHAR_MASK_BITS
	or		%1, CHAR_FLAG
%endmacro

%macro unmask_char 1
	shr		%1, CHAR_MASK_BITS 
%endmacro

%macro mask_double 1
	shl		%1, DOUBLE_MASK_BITS
	or		%1, DOUBLE_FLAG
%endmacro

%macro unmask_double 1
	shr		%1, DOUBLE_MASK_BITS
%endmacro

%macro mask_cons 1
	shl		%1, CONS_MASK_BITS
	or		%1, CONS_FLAG
%endmacro

%macro unmask_cons 1
	shr		%1, CONS_MASK_BITS
%endmacro

%macro add_masked_ints 2
	add		%1, %2
	sub		%1, INT_FLAG
%endmacro

%macro sub_masked_ints 2
	sub		%1, %2
	or		%1, INT_FLAG
%endmacro
