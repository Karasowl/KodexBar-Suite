.PHONY: test install uninstall check

test:
	python3 -m unittest discover -s tests -v

install:
	./install.sh

uninstall:
	./uninstall.sh

check: test
	python3 -m py_compile ai tests/test_ai.py tests/static_checks.py
	bash -n install.sh uninstall.sh
	python3 tests/static_checks.py
