Example LispKit Lisp Programs
=============================

This directory contains some sample LispKit Lisp programs.

  - sumn: Adds the numbers from 1 to N.
  - fib:  Computes the Nth number in the Fibonacci sequence.
  - diff: Simple differentiation of an argument which is a nesting of
          expressions of the form `(ADD <a> <b>)` and `(MUL <a> <b>)`.
		  Differentiation is performed in the symbol `X`
  - Sqrt: Simple square-root calculator.  This program tests the MAP data
          type.  It creates a map from <n²> → <n> for <n> from 1 to 1000, and
		  looks up the input argument in this map.
  - calc: A simple calculator that uses parser combinators instead of the
          CFG shift/reduce parser-generator.
  - yinyang: An implementation of the [yin-yang puzzle](http://en.wikipedia.org/wiki/Call-with-current-continuation)

