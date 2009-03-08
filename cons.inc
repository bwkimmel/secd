%macro lcons 1
	mov		[cons + %1], %1
%endmacro
