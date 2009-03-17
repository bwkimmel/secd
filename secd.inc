; vim: filetype=nasm
%define SECD_TYPEMASK	0x07
%define SECD_CONS		0x00
%define SECD_ATOM		0x01
%define SECD_SYMBOL		0x00 | SECD_ATOM
%define SECD_NUMBER		0x02 | SECD_ATOM
%define SECD_BOOLEAN	0x04 | SECD_ATOM
