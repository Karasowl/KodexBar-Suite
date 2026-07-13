.PHONY: test check kodexbar-check install uninstall

test:
	$(MAKE) -C packages/ai-cli-control test
	node packages/kodexbar/tests/provider-logic.test.js

check:
	$(MAKE) -C packages/ai-cli-control check
	$(MAKE) kodexbar-check
	bash -n install.sh uninstall.sh
	if grep -n '[[:blank:]]$$' README.md README.es.md NOTICE.md LICENSE Makefile install.sh uninstall.sh .gitignore; then exit 1; fi
	git diff --check

kodexbar-check:
	if test -d packages/kodexbar/.git; then \
		bash packages/kodexbar/scripts/validate.sh; \
	else \
		check_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/kodexbar-suite-check.XXXXXX")"; \
		trap 'rm -rf "$$check_dir"' EXIT INT TERM; \
		cp -a packages/kodexbar/. "$$check_dir/"; \
		git -C "$$check_dir" init --quiet; \
		git -C "$$check_dir" add -A; \
		bash "$$check_dir/scripts/validate.sh"; \
	fi

install:
	./install.sh

uninstall:
	./uninstall.sh
