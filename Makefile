include Rules.mk

SUBDIRS = secd lispkit example scheme calc

clean-all: clean
	for dir in $(SUBDIRS); do \
		$(MAKE) --directory=$$dir clean; \
	done
