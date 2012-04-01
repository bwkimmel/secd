TOPDIR = ..

all: TestLex.lob

run: TestLex.lob
	@echo ")) " > .init
	@cat TestLex.lob .init - | $(SECD)
	@rm -f .init

include $(TOPDIR)/Rules.mk
