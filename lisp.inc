; vim: filetype=nasm

%macro	car 1
	shr		dword %1, 16
%endmacro

%macro	cdr	1
	and		dword %1, 0xffff
%endmacro

%macro	lcar 1
	lcons	dword %1
	car		%1
%endmacro

%macro	lcdr 1
	lcons	dword %1
	cdr		%1
%endmacro
	
