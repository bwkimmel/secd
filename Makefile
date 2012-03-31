include Rules.mk

SUBDIRS = secd lispkit test scheme calc

clean-all:
	for dir in $(SUBDIRS); do \
		$(MAKE) --directory=$$dir clean; \
	done
