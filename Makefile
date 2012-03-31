include Rules.mk

SUBDIRS = secd lispkit test scheme calc

clean-all: clean
	for dir in $(SUBDIRS); do \
		$(MAKE) --directory=$$dir clean; \
	done
