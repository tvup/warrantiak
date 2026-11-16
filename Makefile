PREFIX ?= /usr/local
_INSTDIR ?= $(DESTDIR)$(PREFIX)
BINDIR ?= $(_INSTDIR)/bin
MANDIR ?= $(_INSTDIR)/share/man
DATADIR ?= $(_INSTDIR)/share/warrantiak
LIBDIR ?= $(DATADIR)/lib
LIB_FILES := $(wildcard lib/*.sh lib/*.py)
TASK_DONE = echo -e "\n✓ $@ done\n"
SHELL := $(shell which bash)

MOCK_PORT ?= 18765

.PHONY: all help install uninstall reinstall test mock-asus

all:
	@echo "Usage:"
	@echo "  make install"
	@echo "  make reinstall"
	@echo "  make uninstall"
	@echo "  make test        run tests against the local ASUS mock"
	@echo "  make mock-asus   start the local ASUS mock on port $(MOCK_PORT)"

test:
	MOCK_PORT=$(MOCK_PORT) bash test/test_asus.sh

mock-asus:
	python3 test/asus_mock/server.py --port $(MOCK_PORT)

help:
	$(MAKE) all
	@$(TASK_DONE)

install:
	install -d -m 0755 $(BINDIR) $(LIBDIR)
	install -m 0755 warrantiak $(BINDIR)/warrantiak
	rm -f $(LIBDIR)/*.sh $(LIBDIR)/*.py
	install -m 0644 $(LIB_FILES) $(LIBDIR)/
	@$(TASK_DONE)

uninstall:
	rm -f $(BINDIR)/warrantiak
	rm -rf $(DATADIR)
	@$(TASK_DONE)

# Remove the installed copy and install again from the local files.
reinstall:
	$(MAKE) uninstall
	$(MAKE) install
	@$(TASK_DONE)
