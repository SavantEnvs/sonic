#!/usr/bin/env bash
#
# mayhem/test.sh — RUN sonic's own unit tests plus known-answer CLI runs (built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# 1) Upstream's unit tests (tests/runtests.c). They are assert()-based and print "All tests passed."
#    only at the very end, so a neutered/no-op binary (no output) counts as a failure.
passed=0; failed=0
if [ ! -x "$SRC/sonic_unit_test" ] || [ ! -x "$SRC/sonic_cli" ]; then
  echo "sonic_unit_test / sonic_cli missing — mayhem/build.sh should have built them" >&2
  emit_ctrf "sonic-tests" 0 1 0; exit 1
fi
if out=$("$SRC/sonic_unit_test" 2>&1) && [ "$out" = "All tests passed." ]; then
  echo "PASS unit tests"; passed=$((passed+1))
else
  echo "FAIL unit tests: $out"; failed=$((failed+1))
fi

# 2) Known-answer runs of the sonic CLI on the shipped sample recordings: exact output size + sha256.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
check_cli() {  # <name> <expected-size> <expected-sha256> <sonic args…>
  local name="$1" size="$2" sha="$3"; shift 3
  if "$SRC/sonic_cli" "$@" "$work/out.wav" >/dev/null 2>&1 \
     && [ "$(stat -c %s "$work/out.wav")" = "$size" ] \
     && [ "$(sha256sum "$work/out.wav" | cut -d' ' -f1)" = "$sha" ]; then
    echo "PASS $name"; passed=$((passed+1))
  else
    echo "FAIL $name"; failed=$((failed+1))
  fi
  rm -f "$work/out.wav"
}
# sonic_cli [opts] in.wav out.wav — the output path is appended by check_cli, so put the input last.
check_cli "speed-2x-mono" 1022200 faadbb862045ca9e979ed102a626c23270a90f6868ecc44642e4e288959b19fa -s 2.0 "$SRC/samples/talking.wav"
check_cli "pitch-rate-stereo" 784496 5d1605c8a5ca6f64fa522205f7601c65a0425965c280a3273bf8ae2c7aa7e2e0 -p 1.5 -r 1.2 "$SRC/samples/stereo_test.wav"

emit_ctrf "sonic-tests" "$passed" "$failed" 0
