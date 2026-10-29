#!/usr/bin/env bash
# mayhem/build.sh — builds the sanitized fuzz harnesses (+ standalone reproducers), the AFL-instrumented
# CLI target, and the project's own unit tests / CLI with NORMAL flags (run by mayhem/test.sh).
# Runs in the commit image as `mayhem` in /mayhem. Sonic has no dependencies beyond libc/libm, so
# the build is trivially re-runnable and air-gapped.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT=/mayhem
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Library sources, sanitized with DWARF 3 so backtraces resolve project lines.
LIB_SRCS=(sonic.c)
# shift-base is relaxed (everything else in ASan+UBSan stays halting): sonic's fixed-point DSP does
# `x << 8` / `(...) << 1` on negative ints in every resampling pass (sonic.c:555, :931) — benign on
# every supported compiler, but it trips on the first seed and leaves the targets with 0 edges.
FUZZ_CFLAGS="$SANITIZER_FLAGS -fno-sanitize=shift-base $DEBUG_FLAGS -O1 -fPIC -pthread -I$SRC"

# Disable LeakSanitizer at build time (ASan/UBSan stay on).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$SCRATCH/lsan_off.o"

# libFuzzer harnesses (+ standalone reproducers). fuzz_sonic is upstream's in-tree harness.
$CC -c $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" -o "$SCRATCH/standalone_main.o"
for h in fuzz_sonic:tests/fuzz_main.c fuzz_sonic_api:mayhem/fuzz_sonic_api.c; do
  name="${h%%:*}" ; src="${h#*:}"
  $CC $FUZZ_CFLAGS $LIB_FUZZING_ENGINE "$src" "${LIB_SRCS[@]}" "$SCRATCH/lsan_off.o" -lm -o "$OUT/$name"
  $CC $FUZZ_CFLAGS "$src" "${LIB_SRCS[@]}" "$SCRATCH/standalone_main.o" "$SCRATCH/lsan_off.o" -lm -o "$OUT/$name-standalone"
done

# File-input CLI target (legacy `sonic-fuzz`: `sonic @@ /dev/null`), AFL-instrumented.
afl-clang-fast $FUZZ_CFLAGS main.c wave.c sonic.c "$SCRATCH/lsan_off.o" -lm -o "$OUT/sonic-fuzz"

# Test/oracle build: project's NORMAL flags (as in upstream's Makefile), independent of the above.
NORMAL_CFLAGS="-Wall -Wno-unused-function -g -ansi -fPIC -pthread -I$SRC $COVERAGE_FLAGS"
$CC $NORMAL_CFLAGS -o "$OUT/sonic_unit_test" tests/runtests.c tests/sonic_api_test.c \
    tests/input_clamping_test.c tests/genwave.c sonic.c -lm
$CC $NORMAL_CFLAGS -o "$OUT/sonic_cli" main.c wave.c sonic.c -lm
