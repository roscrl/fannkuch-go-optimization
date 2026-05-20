#!/usr/bin/env bash
set -euo pipefail

N=${1:-12}
THREADS=${THREADS:-4}
mkdir -p bin

UNAME_S=$(uname -s)
UNAME_M=$(uname -m)
RUN_PREFIX=""
GOOS_TARGET="$(go env GOOS)"
RUST_TARGET=""
C_ARCH_FLAGS=()

case "${UNAME_S}-${UNAME_M}" in
  Darwin-arm64)
    # The fetched Rust/C programs are x86_64 SIMD programs. Build x86_64 and
    # run through Rosetta so all four binaries are comparable locally.
    RUN_PREFIX="arch -x86_64 "
    GOOS_TARGET="darwin"
    RUST_TARGET="x86_64-apple-darwin"
    C_ARCH_FLAGS=(-arch x86_64)
    ;;
  Darwin-x86_64)
    GOOS_TARGET="darwin"
    RUST_TARGET="x86_64-apple-darwin"
    ;;
  Linux-x86_64)
    GOOS_TARGET="linux"
    RUST_TARGET="x86_64-unknown-linux-gnu"
    ;;
  *)
    echo "Unsupported benchmark host ${UNAME_S}-${UNAME_M}; edit bench.sh for your target." >&2
    exit 1
    ;;
esac

GOARCH=amd64 GOOS="${GOOS_TARGET}" go build -gcflags='-B' -o bin/fannkuch_go_orig_amd64 fannkuch_orig.go
GOARCH=amd64 GOOS="${GOOS_TARGET}" go build -gcflags='-B' -o bin/fannkuch_go_opt_amd64 fannkuch_go_opt.go

"${CC:-clang}" "${C_ARCH_FLAGS[@]}" -O3 -march=x86-64-v3 -mssse3 -msse4.1 -pthread \
  -Wno-implicit-function-declaration -o bin/fannkuch_c_amd64 fannkuch_c.c

RUSTFLAGS='-C target-feature=+ssse3,+sse4.1 -C target-cpu=x86-64-v3' \
  cargo build --release --target "${RUST_TARGET}"
cp "target/${RUST_TARGET}/release/fannkuch_rust" bin/fannkuch_rust_amd64

hyperfine --warmup 1 -r 3 \
  "THREADS=${THREADS} ${RUN_PREFIX}./bin/fannkuch_go_orig_amd64 ${N}" \
  "THREADS=${THREADS} ${RUN_PREFIX}./bin/fannkuch_go_opt_amd64 ${N}" \
  "RAYON_NUM_THREADS=${THREADS} ${RUN_PREFIX}./bin/fannkuch_rust_amd64 ${N}" \
  "${RUN_PREFIX}./bin/fannkuch_c_amd64 -t ${THREADS} ${N}"
