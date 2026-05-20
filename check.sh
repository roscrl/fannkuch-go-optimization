#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}
mkdir -p bin

UNAME_S=$(uname -s)
UNAME_M=$(uname -m)
RUN=()
GOOS_TARGET="$(go env GOOS)"
RUST_TARGET=""
C_ARCH_FLAGS=()

case "${UNAME_S}-${UNAME_M}" in
  Darwin-arm64)
    RUN=(arch -x86_64)
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
    echo "Unsupported check host ${UNAME_S}-${UNAME_M}; edit check.sh for your target." >&2
    exit 1
    ;;
esac

GOARCH=amd64 GOOS="${GOOS_TARGET}" go build -gcflags='-B' -o bin/fannkuch_go_orig_amd64 fannkuch_orig.go
GOARCH=amd64 GOOS="${GOOS_TARGET}" go build -gcflags='-B' -o bin/fannkuch_go_opt_amd64 fannkuch_go_opt.go
"${CC:-clang}" "${C_ARCH_FLAGS[@]}" -O3 -march=x86-64-v3 -mssse3 -msse4.1 -pthread \
  -Wno-implicit-function-declaration -o bin/fannkuch_c_amd64 fannkuch_c.c
RUSTFLAGS='-C target-feature=+ssse3,+sse4.1 -C target-cpu=x86-64-v3' \
  cargo build --release --target "${RUST_TARGET}" >/dev/null
cp "target/${RUST_TARGET}/release/fannkuch_rust" bin/fannkuch_rust_amd64

# Exact expected outputs for the official benchmark-relevant range.
# Note: the fetched C gcc #6 source is not correct for n=5 because its block
# size is odd there; the Benchmarks Game runs larger n (e.g. n=12).
declare -A EXPECTED=(
  [6]=$'49\nPfannkuchen(6) = 10'
  [7]=$'228\nPfannkuchen(7) = 16'
  [8]=$'1616\nPfannkuchen(8) = 22'
  [9]=$'8629\nPfannkuchen(9) = 30'
  [10]=$'73196\nPfannkuchen(10) = 38'
  [11]=$'556355\nPfannkuchen(11) = 51'
  [12]=$'3968050\nPfannkuchen(12) = 65'
)

if (( $# )); then
  inputs=("$@")
else
  inputs=(6 7 8 9 10 11 12)
fi

run_bin() {
  local bin=$1 n=$2
  "${RUN[@]}" "$bin" "$n"
}

for n in "${inputs[@]}"; do
  if [[ -z "${EXPECTED[$n]:-}" ]]; then
    echo "No expected output recorded for n=${n}" >&2
    exit 1
  fi

  expected=${EXPECTED[$n]}
  declare -A programs=(
    [go_orig]="./bin/fannkuch_go_orig_amd64"
    [go_opt]="./bin/fannkuch_go_opt_amd64"
    [rust]="./bin/fannkuch_rust_amd64"
    [c]="./bin/fannkuch_c_amd64"
  )

  for name in go_orig go_opt rust c; do
    if [[ $name == rust ]]; then
      got=$(RAYON_NUM_THREADS="$THREADS" "${RUN[@]}" "${programs[$name]}" "$n")
    elif [[ $name == c ]]; then
      got=$("${RUN[@]}" "${programs[$name]}" -t "$THREADS" "$n")
    else
      got=$(THREADS="$THREADS" run_bin "${programs[$name]}" "$n")
    fi

    if [[ "$got" != "$expected" ]]; then
      echo "FAIL ${name} n=${n}" >&2
      echo "expected:" >&2
      printf '%s\n' "$expected" >&2
      echo "got:" >&2
      printf '%s\n' "$got" >&2
      exit 1
    fi
    echo "ok ${name} n=${n}"
  done

done

echo "all correctness checks passed"
