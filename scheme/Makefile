TOPDIR = ..

all: CompileScheme.lob

run: CompileScheme.lob
	@echo ")) " > .init
	@cat CompileScheme.lob .init - | $(SECD)
	@rm -f .init

include $(TOPDIR)/Rules.mk
