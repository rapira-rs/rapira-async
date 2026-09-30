#!/usr/bin/env bash
set -euo pipefail

SUDO=()
if [ "$(id -u)" != 0 ]; then SUDO=(sudo); fi
if command -v apt-get >/dev/null; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y --no-install-recommends \
        build-essential autoconf bison re2c cmake pkg-config git python3 curl \
        ca-certificates clang libclang-dev liburing-dev libssl-dev \
        libcurl4-openssl-dev libxml2-dev libonig-dev libsqlite3-dev zlib1g-dev \
        libffi-dev libicu-dev libpq-dev patchelf procps
else
    "${SUDO[@]}" dnf -y install dnf-plugins-core
    "${SUDO[@]}" dnf config-manager --set-enabled crb
    "${SUDO[@]}" dnf -y install epel-release
    # The base autoconf package supplies Perl modules omitted by autoconf271.
    "${SUDO[@]}" dnf -y install \
        gcc gcc-c++ make autoconf autoconf271 bison re2c cmake pkgconf-pkg-config git python3 \
        curl-minimal ca-certificates clang-devel llvm-devel liburing-devel openssl-devel \
        libcurl-devel libxml2-devel oniguruma-devel sqlite-devel zlib-devel \
        libffi-devel libicu-devel libpq-devel patchelf procps-ng tar gzip xz
fi
