SECD Machine Implementation
===========================

This directory contains an implementation of an
[SECD machine](http://en.wikipedia.org/wiki/SECD_machine) in x86 assembly.  For
details about its implementation, see:

  P. Henderson, "Functional Programming: Application and Implementation",
  Prentice Hall, 1980.


Source Files
------------

  - secd.asm:     The implementation of the SECD machine.
  - main.asm:     The program entry-point
  - string.asm:   The string-store (stores names of tokens, ensuring that the
                  same string does not get stored twice, thus ensuring that
				  we can detect identical tokens).
  - support.asm:  Functions for reading and writing expressions.
  - heap.asm:     A heap implementation for dynamic allocation of arbitrarily
                  sized chunks of memory (used for vector and binary "blob"
				  data types -- not yet completed).

