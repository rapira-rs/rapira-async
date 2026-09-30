# syntax=docker/dockerfile:1
# PHP is built from https://github.com/php/php-src/pull/23997.
# .github/php-async.env pins the same revision used by Make and CI.
FROM rust:1-trixie@sha256:a8a5f0a1e5fe7dfe1d352591e4a1c7dd2c08fd70475cae872cf3458ba0df0546 AS builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /src
COPY scripts/install-build-deps.sh scripts/install-build-deps.sh
RUN bash scripts/install-build-deps.sh && rm -rf /var/lib/apt/lists/*

ENV PHP_SRC=/third-party/php-src-async \
    PHP_ROOT=/root/.local/share/php-async
COPY Makefile Makefile
COPY .github/php-async.env .github/php-configure-flags.txt .github/
COPY scripts/ scripts/
ARG JOBS=8
RUN make build-php-release JOBS="$JOBS"

COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY .cargo/ .cargo/
COPY src/ src/
COPY crates/ crates/
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    cargo build --release --locked --bin rapira && \
    install -m 0755 target/release/rapira /usr/local/bin/rapira && \
    patchelf --set-rpath /root/.local/share/php-async/lib /usr/local/bin/rapira

# Record the runtime packages from this exact build, including liburing and ICU.
RUN ldd /usr/local/bin/rapira /root/.local/share/php-async/bin/php \
    | awk '/=> \/usr\/lib|=> \/lib/ { print $3 }' | xargs -r realpath | sort -u \
    | xargs -r dpkg-query --search \
    | awk 'sub(":$", "", $1) { print $1 }' | sort -u > /runtime-packages.txt

FROM debian:trixie-slim AS runtime
COPY --from=builder /runtime-packages.txt /tmp/runtime-packages.txt
RUN apt-get update && \
    xargs apt-get install -y --no-install-recommends ca-certificates < /tmp/runtime-packages.txt && \
    rm -rf /var/lib/apt/lists/* /tmp/runtime-packages.txt
COPY --from=builder /root/.local/share/php-async/ /root/.local/share/php-async/
COPY --from=builder /usr/local/bin/rapira /usr/local/bin/rapira
COPY --from=builder /src/scripts/check-php.php /usr/local/share/rapira-async/check-php.php
ENV PATH=/root/.local/share/php-async/bin:$PATH \
    PHP_CONFIG=/root/.local/share/php-async/bin/php-config \
    LD_LIBRARY_PATH=/root/.local/share/php-async/lib
RUN rapira --version && php -n /usr/local/share/rapira-async/check-php.php
LABEL org.opencontainers.image.title="Rapira Async" \
      org.opencontainers.image.description="Linux experiment with PHP IO hooks PR #23997" \
      org.opencontainers.image.source="https://github.com/rapira-rs/rapira-async" \
      org.opencontainers.image.licenses="MIT"
WORKDIR /app
ENTRYPOINT ["rapira"]
CMD ["--help"]
