#!/usr/bin/perl

# This script creates the procedures for the functions of the form
# c(a|d)*r.

$MAX_DEPTH = 4;

# Loop up to the maximum depth.
for ($depth = 1; $depth < $MAX_DEPTH; $depth++) {

	# The number of combinations for the current depth is 2^($depth).
	$combinations = 1 << $depth;

	# Loop through all combinations for the current depth.  Each bit in
	# $n represents a car instruction (0) or a cdr instruction (1).
	for ($n = 0; $n < $combinations; $n++) {

		# Construct a string with the a's and d's and also
		# build a list with the corresponding instructions.
		@instr = ();
		$str = "";
		for ($i = 0; $i < $depth; $i++) {
			$value = (($n & (1 << $i)) ? 'd' : 'a');
			push @instr, "lc" . $value . "r";
			$str = $value . $str;
		}		

		# Print out the assembly instructions.
		print "\n";
		print "_c" . $str . "r:\n";		# Label for procedure
		
		# Instructions to load car/cdr.
		for ($i = 0; $i < $depth; $i++) {
			print "\t" . $instr[$i] . "\teax\n";
		}
		
		print "\tret\n";				# Return instruction

	}
}

