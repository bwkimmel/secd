TOPDIR = ..
CLEANFILES = ExpressionCFG.lso ExpressionDFA.lso

all: TestParse.lob Calc.lob

TestParse.lob: ExpressionCFG.lso ExpressionDFA.lso ../util/Cfg.lso ../util/Util.lso

Calc.lob: ExpressionCFG.lso ExpressionDFA.lso ../util/Cfg.lso ../util/Pattern.lso

BuildExpressionCFG.lob: ExpressionSyntax.lso ../util/Cfg.lso

BuildExpressionDFA.lob: ExpressionCFG.lso ../util/Cfg.lso

ExpressionCFG.lso: BuildExpressionCFG.lob
	cat $^ | $(SECD) > $@

ExpressionDFA.lso: BuildExpressionDFA.lob
	cat $^ | $(SECD) > $@

run: run-Calc

include $(TOPDIR)/Rules.mk
