Simple Calculator
=================

This directory contains an implementation of a simple calculator.  It's purpose
is to exercise the context-free grammar processing and pattern matching
functionality.  There are two programs in this directory:

  - Calc.lso:  The calculator takes a list of tokens as an argument and
               evaluates them as a mathematical expression.
  - TestParse.lso:  TestParse takes the same argument as Calc.lso and prints
                    out the corresponding parse tree, but does not evaluate
					the expression.

NOTE: The expression read by the calculator must be enclosed in parentheses
      (i.e., must be a valid LispKit Lisp "list").

To run the calculator, issue the command:

	make run

To run the parser only, issue the command:

	make run-TestParse

The grammar for the calculator may be found in ExpressionSyntax.lso.  The
calculator evaluates arithmetic and comparison expressions on integers.  The
following arithmetic operators are allowed:

  - multiplication (`*`)
  - division (`/`)
  - addition (`+`)
  - subtraction (`-`)

Additionally, parentheses may be used.  Round parentheses (`(`, `)`), square
brackets (`[`, `]`), or curly brackets (`{`, `}`) may be used, as long as they
are properly matched.

The following comparison operators are allowed:

  - less than (`<`)
  - greater than (`>`)
  - less than or equal (`<=`)
  - greater than or equal (`>=`)
  - equal (`==`)
  - not equal (`!=`)

