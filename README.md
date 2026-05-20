# fannkuch-redux Go optimization

A small benchmark workspace for comparing the Benchmarks Game `fannkuch-redux` implementations:

- `fannkuch_orig.go` — fetched Go #3
- `fannkuch_rust.rs` — fetched Rust #6
- `fannkuch_c.c` — fetched C gcc #6
- `fannkuch_go_opt.go` — optimized Go attempt

The optimized Go version packs the permutation into one `uint64` with 16 4-bit lanes, avoiding the original Go hot-loop `[16]int` array copies. Prefix reverse compiles down to scalar shifts/masks plus `BSWAP`.

## Reproduce

Use Nix flakes. First run the correctness assertions:

```bash
nix develop -c ./check.sh
```

Then run the benchmark:

```bash
nix develop -c ./bench.sh 12
```

Or enter the shell first:

```bash
nix develop
./bench.sh 12
```

`check.sh` builds all four binaries and asserts exact expected output for inputs `6..12`.

`bench.sh` builds all four binaries and runs `hyperfine`:

1. original Go
2. optimized Go
3. Rust SIMD version
4. C SIMD version

You can pass a different fannkuch size:

```bash
nix develop -c ./bench.sh 10
```

Set worker count for Rust/C with `THREADS`:

```bash
THREADS=8 nix develop -c ./bench.sh 12
```

## Platform notes

- Yes: for benchmarking, you just run `nix develop -c ./bench.sh 12`.
- For correctness, run `nix develop -c ./check.sh` first.
- On Apple Silicon, the scripts build x86_64 binaries and run them through Rosetta because the fetched Rust/C programs use x86 SIMD intrinsics.
- On x86_64 Linux/macOS, the script runs native x86_64 binaries.
- The Nix dev shell pins Go, Rust, hyperfine, and Linux clang via `flake.lock`. On Darwin, Apple's system clang is used as the linker/compiler for universal `-arch x86_64` support.

## Local result

On the original test machine, 4 threads, `./bench.sh 12`:

| program | mean |
| --- | ---: |
| C gcc #6 | 3.603s |
| Go optimized | 3.854s |
| Rust #6 | 4.398s |
| Go original | 5.126s |

See `NOTES.md` for assembly notes.
