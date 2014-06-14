SECD Machine
============

This project is an implementation of an [SECD machine](http://en.wikipedia.org/wiki/SECD_machine)
in x86 assembly.  For details, please refer to:

  P. Henderson, "Functional Programming: Application and Implementation",
  Prentice Hall, 1980.


Requirements
------------

  - A POSIX-compatible operating system
  - [nasm](http://www.nasm.us)
  - [GNU make](http://www.gnu.org/software/make/)
  - [GNU m4](http://www.gnu.org/software/m4/)



Directory Structure
-------------------

The project is split up into the following components:

  - secd: The SECD machine implementation.
  - lispkit: The original and extended LispKit Lisp compilers.
  - util: A collection of useful LispKit Lisp functions.
  - example: Some example LispKit Lisp programs.
  - meta: An SECD-machine implementation in (extended) LispKit Lisp.
  - calc: A simple calculator pogram
  - scheme: A Scheme compiler (incomplete -- see scheme/README.md for details).

See the README.md files in each component for further details.



File Types
----------

### Source File (.lso)

These are LispKit Lisp source files, which may represent a standalone program or
a file to be included.  A program file may be distinguished from an include file
in that a program file must contain a single object which has the form:

    (LETREC <name>
      (<name> LAMBDA <params>
        ... function body ...
        ) 
        
      ... other definitions ...
        
      )
    
The `<params>` may either be `NIL` or may be a list of variable names.  If
`<params>` is non-`NIL`, the parameters will be read by the SECD machine from
stdin.  The result of the function indicated by `<name>` will be printed to
stdout.


### Object Files (.lob)

These are compiled source files that are interpreted by the SECD machine.  To
compile a source file, issue the following command:

	make <program>.lob

To execute `<program>.lob`, issue:

	make run-<program>

Issuing the above commands will rebuild the SECD-machine and the LispKit Lisp
compiler, if necessary.  It is not necessary to manually issue a "make" command
for the SECD machine or compiler prior to building a LispKit Lisp program.

The arguments to the program are read from stdin and the result is written to
stdout.  Some programs may read directly from stdin via the `GET` opcode, rather
than having the SECD machine provide parse the input as arguments to the main
function.  Use the string "))" to separate the end of arguments to the main
function from input read by the program itself.


License
-------

Copyright (c) 2009 Bradley W. Kimmel

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
