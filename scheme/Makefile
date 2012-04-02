TOPDIR = ..
CLEANFILES = SchemeCFG.lso SchemeDFA.lso

all: TestLex.lob TestParse.lob

TestLex.lob: LexScheme.lso ../util/Util.lso

TestParse.lob: LexScheme.lso SchemeCFG.lso SchemeDFA.lso ../util/Cfg.lso ../util/Util.lso

BuildSchemeCFG.lob: SchemeSyntax.lso ../util/Cfg.lso

BuildSchemeDFA.lob: SchemeCFG.lso ../util/Cfg.lso

SchemeCFG.lso: BuildSchemeCFG.lob
	cat $^ | $(SECD) > $@

SchemeDFA.lso: BuildSchemeDFA.lob
	cat $^ | $(SECD) > $@

test-parse: TestParse.lob
	@echo ")) " > .init
	@cat TestParse.lob .init - | $(SECD)
	@rm -f .init

test-lex: TestLex.lob
	@echo ")) " > .init
	@cat TestLex.lob .init - | $(SECD)
	@rm -f .init

include $(TOPDIR)/Rules.mk
