# fannkuch-redux Go optimization notes

Fetched sources:

- `fannkuch_orig.go` — Benchmarks Game Go #3
- `fannkuch_rust.rs` — Benchmarks Game Rust #6
- `fannkuch_c.c` — Benchmarks Game C gcc #6
- `fannkuch_go_opt.go` — optimized Go attempt

Benchmark command: `./bench.sh 12` on Apple Silicon, building x86_64 binaries and running via Rosetta, 4 worker threads.

| program | mean wall time |
| --- | ---: |
| C gcc #6 (`-march=x86-64-v3`) | 3.603s |
| Go optimized | 3.854s |
| Rust #6 | 4.398s |
| Go original (`-gcflags=-B`) | 5.126s |

The optimized Go version is ~1.33x faster than the fetched Go #3 here, slightly faster than the fetched Rust #6 under this local setup, and ~7% behind the C SIMD version.

## What changed

The original Go code keeps permutations as `[16]int` and repeatedly copies/rotates/reverses 128-byte arrays.  The Rust and C versions keep permutations packed into 16 lanes and use `pshufb`/`vpshufb` shuffle masks.

Go does not expose x86 SIMD intrinsics, so `fannkuch_go_opt.go` packs all 16 values into one `uint64` as 4-bit nibbles:

- low nibble = permutation element 0
- prefix rotate = mask + shifts
- prefix reverse = nibble swap + `bits.ReverseBytes64` (`BSWAP` in amd64 asm) + shift

## Assembly observations

- Original Go hot path contains repeated 128-byte `MOVUPS` copy sequences for `copy(pp[:], p[:])` on `[16]int`.
- Optimized Go hot path uses scalar integer operations and compiles prefix reverse to `SHLQ`/`SHRQ` plus `BSWAP`; no array-copy hot path remains.
- Rust/C hot paths use SSSE3/SSE4 shuffles (`vpshufb`/`pshufb`, `pblendvb`/`vpblend*`) to reverse/rotate byte lanes.

Useful inspection commands:

```bash
go tool objdump -s 'main\.fannkuch' bin/fannkuch_go_orig_amd64
GOARCH=amd64 GOOS=darwin go tool objdump -s 'main\.runTask' bin/fannkuch_go_opt_amd64
otool -Vt bin/fannkuch_c_amd64 | grep -E 'pshufb|pblend|palignr'
otool -Vt bin/fannkuch_rust_amd64 | grep -E 'vpshufb|vpextr|vmovd'
```
