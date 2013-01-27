LispKit Lisp Compiler
=====================

This directory contains original LispKit Lisp compiler and an extended version.
The original version (`APENDIX2.LSO`, `APENDIX2.LOB`) may be found in Appendix 2
of

  P. Henderson, "Functional Programming: Application and Implementation",
  Prentice Hall, 1980.

The transcriptions were obtained from <http://www.ocs.net/~jfurman/lispkit/bookversion>.

The extended version (`compiler.lso`) adds the following:

  - commands to utilize extensions to the SECD instruction set
  - short-circuiting AND/OR
  - proper handling of tail recursion
  - removes requirement to QUOTE numbers
  - support for lazy evaluation (DELAY/FORCE)
  - support for MACROs (see below)

Note that the extended version of the compiler must not use any of these
extensions, as it must be compiled by the original compiler.



Macros
------

In the definitions for a `(LET ...)` or `(LETREC ...)` block, one can
include MACRO definitions.  They have the same syntax as LAMBDA
definitions except with the keyword MACRO in place of LAMBDA.
Macro definitions do not get compiled.
References to macros are processed at *compile* time, rather than at
run-time:  The macro call is replaced with the body from the macro
definition, with its arguments substituted with the provided
S-expressions.

Example:

    (LET
      (F (TEST (1 2 3) 4 5))
      (TEST MACRO (X Y Z)
        (LIST (QUOTE X) (CONS Y Z))))

While compiling the above, `(TEST (1 2 3) 4 5)` would be replaced by
`(LIST (QUOTE (1 2 3)) (CONS 4 5))`.  Compilation would then continue
as if the code had been written as:

    (LET
      (F (LIST (QUOTE (1 2 3)) (CONS 4 5))))

Note that, if TEST had been a LAMBDA definition, `(TEST (1 2 3) 4 5)`
would be illegal, since `(1 2 3)` would be interpreted as a call to the
function `1`.  Because it is a MACRO, however, `(QUOTE (1 2 3))` is
substituted for `(1 2 3)` *before* proceeding with compilation.



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

