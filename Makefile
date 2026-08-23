PYTHON ?= python3
ASM_LINT := $(PYTHON) tooling/asm_lint.py

.PHONY: lint format format-check test-lint

lint:
	$(ASM_LINT) check

format:
	$(ASM_LINT) format

format-check:
	$(ASM_LINT) check

test-lint:
	$(PYTHON) -m unittest tooling.test_asm_lint
