#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/.github/php-async.env"
PROFILE=${1:?usage: build-php.sh debug|release [--rebuild]}
case "$PROFILE" in
    debug) FLAGS=(--enable-debug --enable-debug-assertions --enable-zend-test); CFLAGS=${CFLAGS:--O0 -g3}; BUILD_TYPE=Debug ;;
    release) FLAGS=(--disable-debug --disable-debug-assertions); CFLAGS=${CFLAGS:--O2 -g}; BUILD_TYPE=Release ;;
    *) echo "Unknown build profile: $PROFILE" >&2; exit 1 ;;
esac
case "${2:-}" in
    '') REBUILD=false ;;
    --rebuild) REBUILD=true ;;
    *) echo "Unknown build option: $2" >&2; exit 1 ;;
esac
test "$(uname -s)" = Linux || { echo 'rapira-async requires Linux' >&2; exit 1; }
PHP_SRC=$(realpath -m "${PHP_SRC:-$ROOT/../../third-party/php-src-async}")
PHP_ROOT=$(realpath -m "${PHP_ROOT:-$HOME/.local/share/php-async}")
PREFIX="$PHP_ROOT"
case "$PREFIX" in
    /|"$HOME"|"$ROOT"|"$PHP_SRC") echo "Invalid PHP install directory: $PREFIX" >&2; exit 1 ;;
esac
BUILD="$ROOT/target/php-build/$PROFILE"
IOR_SRC="$ROOT/target/ior-src"
IOR_BUILD="$ROOT/target/ior-build/$PROFILE"
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN)}

if [ ! -d "$PHP_SRC" ]; then
    git init -q "$PHP_SRC"
    git -C "$PHP_SRC" remote add origin "$PHP_REPOSITORY"
    git -C "$PHP_SRC" fetch --depth 1 origin "$PHP_REF"
    if ! git -C "$PHP_SRC" cat-file -e "$PHP_COMMIT^{commit}" 2>/dev/null; then
        git -C "$PHP_SRC" fetch --depth 1 origin "$PHP_COMMIT"
    fi
    git -C "$PHP_SRC" checkout --detach "$PHP_COMMIT"
fi
if [ "$(git -C "$PHP_SRC" rev-parse HEAD)" != "$PHP_COMMIT" ]; then
    echo "Expected PR #23997 commit $PHP_COMMIT in $PHP_SRC (see .github/php-async.env)" >&2
    exit 1
fi

# Both profiles replace the same install; their build directories stay separate.
ID=$({
    cat "$ROOT/.github/php-async.env" "$ROOT/.github/php-configure-flags.txt" "$0"
    printf '%s\n' "$PROFILE" "$PREFIX" "$PHP_SRC" "$CFLAGS" "${CC:-cc}"
    git -C "$PHP_SRC" diff HEAD
} | sha256sum | cut -d ' ' -f1)
if [ "$REBUILD" = false ] && [ -x "$PREFIX/bin/php" ] && [ -f "$PREFIX/lib/libphp.so" ] && \
   [ "$(cat "$PREFIX/.rapira-build-id" 2>/dev/null || true)" = "$ID" ]; then
    "$PREFIX/bin/php" -n "$ROOT/scripts/check-php.php"
    exit 0
fi

pkg-config --atleast-version=2.2 liburing
if [ ! -d "$IOR_SRC/.git" ]; then
    git init -q "$IOR_SRC"
fi
if [ "$(git -C "$IOR_SRC" rev-parse HEAD 2>/dev/null || true)" != "$IOR_COMMIT" ]; then
    git -C "$IOR_SRC" fetch --depth 1 "$IOR_REPOSITORY" "$IOR_COMMIT"
    git -C "$IOR_SRC" checkout -q --detach FETCH_HEAD
fi
test "$(git -C "$IOR_SRC" rev-parse HEAD)" = "$IOR_COMMIT"

# Remove the previous install, including the old debug/release subdirectories.
rm -rf -- "$PREFIX"
if [ "$REBUILD" = true ]; then
    rm -rf -- "$BUILD" "$IOR_BUILD"
fi
cmake -S "$IOR_SRC" -B "$IOR_BUILD" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX/ior" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DIOR_WITH_URING=ON -DIOR_WITH_THREADS=ON \
    -DIOR_BUILD_TESTS=OFF -DIOR_BUILD_BENCH=OFF
cmake --build "$IOR_BUILD" --parallel "$JOBS"
cmake --install "$IOR_BUILD"

mkdir -p "$BUILD" "$PREFIX/etc/conf.d"
if [ "$(cat "$BUILD/.configure-id" 2>/dev/null || true)" != "$ID" ]; then
    if [ -f "$BUILD/Makefile" ]; then
        make -C "$BUILD" distclean
    fi
    (cd "$PHP_SRC" && ./buildconf --force)
    mapfile -t COMMON_FLAGS < "$ROOT/.github/php-configure-flags.txt"
    (cd "$BUILD" && CFLAGS="$CFLAGS" "$PHP_SRC/configure" \
        --prefix="$PREFIX" \
        --with-config-file-path="$PREFIX/etc" \
        --with-config-file-scan-dir="$PREFIX/etc/conf.d" \
        "${COMMON_FLAGS[@]}" --with-ior="$PREFIX/ior" "${FLAGS[@]}")
    printf '%s\n' "$ID" > "$BUILD/.configure-id"
fi
make -C "$BUILD" -j"$JOBS"
make -C "$BUILD" install
"$PREFIX/bin/php" -n "$ROOT/scripts/check-php.php"
printf '%s\n' "$PHP_COMMIT" > "$PREFIX/PHP_COMMIT"
printf '%s\n' "$PROFILE" > "$PREFIX/PHP_PROFILE"
printf '%s\n' "$ID" > "$PREFIX/.rapira-build-id"
