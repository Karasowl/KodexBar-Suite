.PHONY: test check kodexbar-check install uninstall

test:
	$(MAKE) -C packages/ai-cli-control test
	node packages/kodexbar/tests/provider-logic.test.js
	node packages/kodexbar/tests/local-models-static.test.js

check:
	$(MAKE) -C packages/ai-cli-control check
	$(MAKE) kodexbar-check
	bash -n install.sh uninstall.sh
	if grep -n '[[:blank:]]$$' README.md README.es.md NOTICE.md LICENSE Makefile install.sh uninstall.sh .gitignore; then exit 1; fi
	git diff --check

kodexbar-check:
	bash packages/kodexbar/scripts/validate.sh

install:
	./install.sh

uninstall:
	./uninstall.sh
