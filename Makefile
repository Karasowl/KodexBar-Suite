.PHONY: test check kodexbar-check system-package-check deb rpm install uninstall

test:
	$(MAKE) -C packages/ai-cli-control test
	node packages/kodexbar/tests/provider-logic.test.js
	node packages/kodexbar/tests/local-models-static.test.js
	node packages/kodexbar/tests/skills-static.test.js
	python3 tests/test_root_install.py
	python3 tests/test_system_packaging.py

check:
	$(MAKE) -C packages/ai-cli-control check
	$(MAKE) kodexbar-check
	$(MAKE) system-package-check
	bash -n install.sh uninstall.sh packaging/aur/kodexbar-suite.install packaging/aur/reload-plasma-after-upgrade packaging/deb/build-deb.sh packaging/rpm/build-rpm.sh packaging/system/stage-package.sh
	sh -n packaging/deb/postinst
	if grep -n '[[:blank:]]$$' README.md README.es.md INSTALL.md INSTALL.es.md NOTICE.md LICENSE Makefile install.sh uninstall.sh packaging/README.md packaging/aur/kodexbar-suite.install packaging/aur/reload-plasma-after-upgrade packaging/deb/build-deb.sh packaging/deb/control.in packaging/deb/postinst packaging/rpm/build-rpm.sh packaging/rpm/kodexbar-suite.spec.in packaging/system/stage-package.sh .gitignore; then exit 1; fi
	git diff --check

kodexbar-check:
	bash packages/kodexbar/scripts/validate.sh

system-package-check:
	python3 tests/test_system_packaging.py

deb:
	./packaging/deb/build-deb.sh

rpm:
	./packaging/rpm/build-rpm.sh

install:
	./install.sh

uninstall:
	./uninstall.sh
