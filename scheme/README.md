Scheme Compiler
===============

This directory contains a (currently incomplete) implementation of a
[Scheme (R5RS)](http://www.schemers.org/Documents/Standards/R5RS/) compiler.



Lexer
-----

To test the lexer, issue the command:

	make test-lex

The program reads Scheme tokens from standard input and prints a description of
them to standard output.



Parser
------

To test the parser, issue the command:

	make test-parse

The program reads the source for a Scheme program from standard input and prints
the parse tree to standard output.



KNOWN ISSUES
------------

This program pushes against the limits of the SECD machine (64K cons-cells) and
will likely crash if it is fed a Scheme program that is too large.  The reason
for the 64K limit is that each cell in the SECD machine is 32-bits.  A cons pair
(used for building lists) is stored in a single cell as two 16-bit cell indices.

The reason that test-parse is slow is because it needs to rebuild a large MAP
data structure before it can start parsing.  If the map could be loaded directly,
rather than have it rebuild the map from a list of entries, it would be much
faster.  Unfortunately attempting to load the MAP on startup causes the 64K
limit to be exceeded.

I have plans to modify the SECD machine to read its program in a binary format,
rather than parsing text from stdin.  This will allow for optimizing the layout
of compiled LispKit Lisp programs (for example, identical tokens could share the
same location in memory).  This will help alleviate this issue.


