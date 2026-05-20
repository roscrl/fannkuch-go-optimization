// The Computer Language Benchmarks Game
// https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
//
// Optimized Go version derived from fannkuchredux-go-3 and the packed
// permutation strategy used by the Rust/C SIMD entries.  The permutation is
// stored as sixteen 4-bit lanes in one uint64; prefix rotate/reverse become
// shifts, masks, and one byte-swap instead of array copies.

package main

import (
	"flag"
	"fmt"
	"log"
	"math/bits"
	"os"
	"runtime"
	"strconv"
)

const MAX_N = 16
const identity uint64 = 0xFEDCBA9876543210
const loNibbles uint64 = 0x0F0F0F0F0F0F0F0F

type count16 [16]uint8

type task struct {
	current uint64
	count   count16
	marker  uint8
	idx     int
}

type result struct {
	checksum int
	maxFlips int
}

var prefixMask = [16]uint64{
	0x000000000000000F,
	0x00000000000000FF,
	0x0000000000000FFF,
	0x000000000000FFFF,
	0x00000000000FFFFF,
	0x0000000000FFFFFF,
	0x000000000FFFFFFF,
	0x00000000FFFFFFFF,
	0x0000000FFFFFFFFF,
	0x000000FFFFFFFFFF,
	0x00000FFFFFFFFFFF,
	0x0000FFFFFFFFFFFF,
	0x000FFFFFFFFFFFFF,
	0x00FFFFFFFFFFFFFF,
	0x0FFFFFFFFFFFFFFF,
	0xFFFFFFFFFFFFFFFF,
}

func rotatePrefix(x uint64, k int) uint64 {
	mask := prefixMask[k]
	prefix := x & mask
	return (x &^ mask) | (prefix >> 4) | ((prefix & 0xF) << (uint(k) << 2))
}

func reversePrefix(x uint64, k int) uint64 {
	shift := uint(k) << 2
	mask := prefixMask[k]
	prefix := x & mask
	prefix = ((prefix & loNibbles) << 4) | ((prefix >> 4) & loNibbles)
	prefix = bits.ReverseBytes64(prefix) >> (60 - shift)
	return (x &^ mask) | prefix
}

func advanceArray(x uint64, count *count16) uint64 {
	for layer := 1; layer < 16; layer++ {
		x = rotatePrefix(x, layer)
		count[layer]++
		if count[layer] <= uint8(layer) {
			break
		}
		count[layer] = 0
	}
	return x
}

func runTask(t task) result {
	current := t.current
	count := t.count
	checksum := 0
	maxFlips := 0
	for count[t.idx] == t.marker {
		tmp := current
		first := tmp & 0xF
		if first != 0 {
			revCount := 0
			for first != 0 {
				next := (tmp >> (uint(first) << 2)) & 0xF
				tmp = reversePrefix(tmp, int(first))
				first = next
				revCount++
			}
			if count[1] == 0 {
				checksum += revCount
			} else {
				checksum -= revCount
			}
			if maxFlips < revCount {
				maxFlips = revCount
			}
		}
		current = advanceArray(current, &count)
	}
	return result{checksum: checksum, maxFlips: maxFlips}
}

func fannkuch(n int) (int, int) {
	if n > MAX_N {
		log.Fatalf("Max value accepted for N: %d", MAX_N)
	}
	if n < 1 {
		return 0, 0
	}
	if n == 1 {
		return 0, 0
	}
	if n == 2 {
		return -1, 1
	}

	current := uint64(identity)
	arrays1 := make([]uint64, n)
	for i := 0; i < n; i++ {
		arrays1[i] = current
		current = rotatePrefix(current, n-1)
	}

	ntasks := n * (n - 1)
	tasks := make(chan task, ntasks)
	results := make(chan result, ntasks)
	workers := runtime.GOMAXPROCS(0)
	for w := 0; w < workers; w++ {
		go func() {
			for t := range tasks {
				results <- runTask(t)
			}
		}()
	}

	for r1 := 0; r1 < n; r1++ {
		current = arrays1[r1]
		var count count16
		count[n-1] = uint8(r1)

		arrays2 := make([]uint64, n-1)
		for r2 := 0; r2 < n-1; r2++ {
			arrays2[r2] = current
			current = rotatePrefix(current, n-2)
		}
		for r2 := 0; r2 < n-1; r2++ {
			c := count
			c[n-2] = uint8(r2)
			tasks <- task{current: arrays2[r2], count: c, marker: uint8(r2), idx: n - 2}
		}
	}
	close(tasks)

	checksum := 0
	maxFlips := 0
	for i := 0; i < ntasks; i++ {
		r := <-results
		checksum += r.checksum
		if maxFlips < r.maxFlips {
			maxFlips = r.maxFlips
		}
	}
	return checksum, maxFlips
}

func threadCount() int {
	if s := os.Getenv("THREADS"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 {
			return n
		}
	}
	return 4
}

func main() {
	n := 12
	flag.Parse()
	if flag.NArg() == 1 {
		n, _ = strconv.Atoi(flag.Arg(0))
	}
	runtime.GOMAXPROCS(threadCount())
	checksum, maxFlips := fannkuch(n)
	fmt.Printf("%d\nPfannkuchen(%d) = %d\n", checksum, n, maxFlips)
}
