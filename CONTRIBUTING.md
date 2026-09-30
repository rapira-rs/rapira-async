# Work on Rapira Async

Use Linux and the Rust toolchain in `rust-toolchain.toml`. PHP comes from [PR #23997](https://github.com/php/php-src/pull/23997). Its revision and the `ior` revision are in `.github/php-async.env`.

## Dependencies

Debian or Ubuntu:

```sh
sudo apt-get install build-essential autoconf bison re2c cmake pkg-config git \
    python3 curl clang libclang-dev liburing-dev libssl-dev libcurl4-openssl-dev \
    libxml2-dev libonig-dev libsqlite3-dev zlib1g-dev libffi-dev libicu-dev libpq-dev
```

The build requires Autoconf 2.71 or newer and liburing 2.2 or newer. `scripts/install-build-deps.sh` installs the dependencies on Debian/Ubuntu and Rocky Linux 9; on Rocky, the PHP build selects the separate `autoconf271` tools. `ior` also builds its thread backend, which works when the kernel cannot use io_uring.

## Build and editor

```sh
make build-debug                 # PHP debug + Rapira debug
make build-release               # PHP release + Rapira release
make build-debug JOBS=8           # limit PHP compiler jobs
make build-php-debug              # replace the install with a clean PHP debug build
make build-php-release            # replace the install with a clean PHP release build
```

PHP source defaults to `../../third-party/php-src-async`. Set `PHP_SRC` to another checkout of the pinned PR revision if needed. Existing checkouts must have that revision checked out. The build never resets an existing checkout. Build files stay in `target/php-build/{debug,release}`. PHP installs directly to `~/.local/share/php-async`, with `ior` in its `ior` subdirectory. `PHP_ROOT` can change this install directory.

`make build-php-debug` and `make build-php-release` delete the entire previous install and the selected profile's build directories, then rebuild PHP and update the editor configuration. Only one PHP profile is installed at a time. The combined `make build-debug` and `make build-release` targets reuse a matching PHP install; otherwise they replace it before building Rapira.

`target/php-async` points to the install. Cargo uses `scripts/php-config` and this install's library directory, including when the shell has another `PHP_CONFIG`. `make activate-debug` or `make activate-release` refreshes configuration for the installed profile and rejects a profile mismatch. Cargo regenerates its C build and PHP bindings after a profile change. Rebuild before running a binary from the other profile.

The build generates `target/clangd/compile_commands.json` for `.clangd`. This file includes the PHP PR source and its generated configuration headers. It also generates local `.zed/settings.json` from `.zed/settings.template.json`, with the async PHP CLI first on the terminal PATH. Open this repository as a Zed project. The project tasks run Make or the async PHP CLI. The debugger builds and selects debug PHP before starting Rapira.

## Checks

```sh
make check-php
make test
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo clippy -p tests --features e2e --tests -- -D warnings
```

`make test_nts` runs unit tests. `make test_e2e` builds Rapira and runs the HTTP and process tests sequentially. Extension tests use their existing skip checks for optional external extensions. CI requires the bundled OpenSSL extension. `make coverage` needs cargo-llvm-cov and llvm-tools-preview. `make stubs` regenerates the C argument headers with the async PHP CLI and the PR's `gen_stub.php`.

The workspace includes the SAPI, HTTP plugin, static-file middleware, process supervisor, network layer, observability server, configuration, scoreboard, and tests. Unit tests stay in their crate. Tests that need PHP, files, sockets, or processes stay in `crates/tests/tests/e2e`.

## CI and containers

Linux CI builds the pinned PHP PR in debug and release profiles on x86_64 and aarch64. All PHP builds use `scripts/build-php.sh` and `.github/php-configure-flags.txt`. To update the PR, update `.github/php-async.env` and the local source checkout together.

```sh
docker build -t rapira-async .
docker run --rm --network host -v "$PWD/examples:/app:ro" rapira-async serve /app/rapira.toml
```

The Docker image contains the release PHP install at `/root/.local/share/php-async`. It includes the PHP CLI and Rapira. Published images use `-php-async` tags. Linux archives and packages contain the same PR build.

## Releases

Use Conventional Commits: `fix: ...` and `feat: ...` trigger a release pull request. A history containing only `chore: ...` commits (including dependency updates) does not. Re-running the Release workflow does not force a release. Merge the generated release pull request to build and publish its artifacts.
