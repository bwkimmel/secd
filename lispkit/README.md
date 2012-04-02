LispKit Lisp Compiler
=====================

This directory contains original LispKit Lisp compiler and an extended version.
The original version (`APENDIX2.LSO`, `APENDIX2.LOB`) may be found in Appendix 2
of

  P. Henderson, "Functional Programming: Application and Implementation",
  Prentice Hall, 1980.

The extended version (`compiler.lso`) adds the following:

	- commands to utilize extensions to the SECD instruction set
	- short-circuiting AND/OR
	- proper handling of tail recursion
	- removes requirement to QUOTE numbers

Note that the extended version of the compiler must not use any of these
extensions, as it must be compiled by the original compiler.



Compiling the Compiler
----------------------

To compile the extended compiler, issue the command:

	make

Compilation of the compiler proceeds in the following manner:

	1. `APENDIX2.LOB` (transcribed from the Henderson book) is used to compile
	   `APENDIX2.LSO` (also transcribed from the book).  By having the compiler
	   compile itself, we ensure that the transcription is accurate.  This
	   compiler is written to `primitive-compiler.lob`
	2. `primitive-compiler.lob` is used to compile the extended compiler
	   (`compiler.lso`).  This compiler is written to `compiler.lob.tmp`.
	3. Finally, `compiler.lob.tmp` is used to compile `compiler.lso` again.
	   This ensures that the compiler is working well enough to compile itself.
	   This compiler is written to `compiler.lob` and used to compile other
	   programs.

