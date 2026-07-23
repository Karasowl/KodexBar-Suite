.PHONY: test install uninstall check

test:
	python3 -m unittest discover -s tests -v

install:
	./install.sh

uninstall:
	./uninstall.sh

check: test
	python3 -m py_compile ai kodexbar-quotas kodexbar-panel kodexbar-tray local-ai recover.py local_ai_drivers/*.py tests/test_ai.py tests/test_kodexbar_quotas.py tests/test_kodexbar_panel.py tests/test_kodexbar_tray.py tests/test_local_ai.py tests/static_checks.py
	bash -n install.sh uninstall.sh
	python3 tests/static_checks.py
