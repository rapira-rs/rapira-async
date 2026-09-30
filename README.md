# Rapira Async

An experimental, Linux-only Rapira fork for the **Polling API additions, IO Hooks, and IO Ring** in [php/php-src PR #23997 — IO hooks PoC](https://github.com/php/php-src/pull/23997). The APIs are experimental. This checkout provides the HTTP server and the build environment for work on them.

```sh
make build-debug
make test
# Or build optimized PHP and Rapira:
make build-release

# Replace the installed PHP with a fresh PHP-only build:
make build-php-debug
make build-php-release
```

PHP sources: `../../third-party/php-src-async` (`PHP_SRC` can override this path). The build creates a missing checkout from the PR. `.github/php-async.env` pins PHP and its `ior` dependency for local builds, Linux CI, and Docker.

PHP installs directly to `~/.local/share/php-async`, with NTS, the embed SAPI, CLI, and `--with-ior`. `make build-php-debug` and `make build-php-release` delete the previous install and rebuild PHP in that directory, then update Cargo, clangd, and Zed through `target/php-async`. Only one PHP profile is installed at a time. `make build-debug` and `make build-release` reuse a matching PHP install or replace it before building Rapira. Rebuild Rapira after switching PHP profiles.

Open this folder in **Zed** after `make build-debug`. Cargo and rust-analyzer use `.cargo/config.toml`; clangd uses the generated compilation database and the PR source checkout. Zed tasks and debugger configurations use the selected async PHP. The debugger builds the debug profile first.

See [CONTRIBUTING.md](CONTRIBUTING.md) for Linux dependencies and build checks.
