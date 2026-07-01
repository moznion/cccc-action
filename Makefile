.DEFAULT_GOAL := all
.PHONY: all lint actionlint shellcheck test

SCRIPTS := scripts/install.sh scripts/run.sh

all: lint test

## lint: run all static checks (actionlint + shellcheck)
lint: actionlint shellcheck

## actionlint: lint GitHub Actions workflows and the composite action
actionlint:
	@command -v actionlint >/dev/null 2>&1 || { echo "actionlint not found: https://github.com/rhysd/actionlint" >&2; exit 1; }
	actionlint

## shellcheck: lint the extracted shell scripts
shellcheck:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found: https://www.shellcheck.net" >&2; exit 1; }
	shellcheck $(SCRIPTS)

## test: run the bats unit tests
test:
	@command -v bats >/dev/null 2>&1 || { echo "bats not found: https://github.com/bats-core/bats-core" >&2; exit 1; }
	bats test
