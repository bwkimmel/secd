; vim: filetype=nasm

%macro	car 1
	shr		dword %1, 16
%endmacro

%macro	cdr	1
	and		dword %1, 0xffff
%endmacro
