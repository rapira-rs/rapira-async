.DEFAULT_GOAL := build-debug

PHP_SRC ?= $(abspath ../../third-party/php-src-async)
PHP_ROOT ?= $(HOME)/.local/share/php-async
JOBS ?= $(shell getconf _NPROCESSORS_ONLN)
export PHP_SRC PHP_ROOT JOBS

PHP_CONFIG := $(CURDIR)/scripts/php-config
PHP_BIN := $(CURDIR)/target/php-async/bin/php
GEN_STUB := $(PHP_SRC)/build/gen_stub.php

.PHONY: build-release build-debug build-php-release build-php-debug \
        php-release php-debug activate-release activate-debug \
        check-php test test_nts test_e2e coverage stubs

build-release: php-release
	cargo build --release --locked --bin rapira

build-debug: php-debug
	cargo build --locked --bin rapira

build-php-release build-php-debug:
	bash scripts/build-php.sh $(patsubst build-php-%,%,$@) --rebuild
	$(MAKE) activate-$(patsubst build-php-%,%,$@)

php-release php-debug:
	bash scripts/build-php.sh $(patsubst php-%,%,$@)
	$(MAKE) activate-$(patsubst php-%,%,$@)

activate-release activate-debug:
	python3 scripts/activate-php.py "$(PHP_ROOT)" "$(PHP_SRC)" "$(patsubst activate-%,%,$@)"

check-php:
	@$(PHP_CONFIG) --version
	$(PHP_BIN) -n scripts/check-php.php

test: test_nts
	$(MAKE) test_e2e

test_nts: check-php
	cargo test --workspace --locked

test_e2e: check-php
	cargo build --locked -p rapira_core --bin rapira
	cargo test --locked -p tests --test e2e --features e2e -- --test-threads=1

stubs: check-php
	@test -f "$(GEN_STUB)" || { echo "gen_stub.php not found at $(GEN_STUB)"; exit 1; }
	@mkdir -p target/stubgen
	@cp "$(GEN_STUB)" target/stubgen/gen_stub.php
	@for stub in $$(find crates -name '*.stub.php'); do \
		"$(PHP_BIN)" target/stubgen/gen_stub.php "$$stub" || exit 1; \
	done

coverage: check-php
	@export RUSTFLAGS="$${RUSTFLAGS:-} -Cllvm-args=-runtime-counter-relocation"; \
	eval "$$(cargo llvm-cov show-env --export-prefix)" && \
	export LLVM_PROFILE_FILE="$$CARGO_LLVM_COV_TARGET_DIR/rapira-%p%c.profraw" && \
	cargo llvm-cov clean --workspace && \
	cargo test --workspace --locked && \
	cargo build --locked -p rapira_core --bin rapira && \
	cargo test --locked -p tests --test e2e --features e2e -- --test-threads=1 && \
	cargo llvm-cov report --workspace --lcov --output-path lcov.info \
		--ignore-filename-regex '(crates/tests/|bindings\.rs$$|/src/main\.rs$$)'
