.PHONY: test lint help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

test: ## Run all bats tests (no Docker required)
	bats tests/bats/

lint: ## Run shellcheck on all shell scripts
	shellcheck bin/devenv bin/build-devenv scripts/install-devenv shared/bash/primitives.sh
