#!/bin/bash
# End-to-end tests driven through the CLI against the fixture bundle. Run with `make test`.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=build/swizzlescope
FIX=build/Fixture.bundle
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
section() { echo "== $*"; }

section "classes in fixture"
out=$($BIN classes "$FIX") || fail "classes exited non-zero"
grep -qx FXBase <<<"$out" || fail "FXBase missing from class list"
grep -qx FXChild <<<"$out" || fail "FXChild missing from class list"

section "header golden files"
for c in FXBase FXChild; do
  $BIN header "$c" "$FIX" > "build/$c.h" || fail "header $c exited non-zero"
  diff -u "Tests/golden/$c.h" "build/$c.h" || fail "header mismatch for $c"
done

section "dump"
dump=$($BIN dump FXBase "$FIX") || fail "dump FXBase exited non-zero"
grep -q 'Instance methods (24)' <<<"$dump" || fail "dump FXBase method count"
grep -q '@56   CGRect _frame;' <<<"$dump" || fail "dump FXBase ivar offset"
nsstring=$($BIN dump NSString) || fail "dump NSString exited non-zero"
grep -q 'length' <<<"$nsstring" || fail "dump NSString should list length"

section "images"
images=$($BIN images) || fail "images exited non-zero"
grep -q 'Foundation.framework' <<<"$images" || fail "images should list Foundation"

section "search"
search=$($BIN search vectorScaled "$FIX") || fail "search exited non-zero"
grep -qx FXBase <<<"$search" || fail "search vectorScaled should find FXBase"

section "loader errors"
if $BIN load /System/Applications/Calculator.app 2>build/err.txt; then fail "Calculator.app should not load"; fi
grep -qi 'application' build/err.txt || fail "expected app error, got: $(cat build/err.txt)"
if $BIN load /bin/ls 2>build/err.txt; then fail "/bin/ls should not load"; fi
grep -qi 'MH_EXECUTE' build/err.txt || fail "expected MH_EXECUTE error, got: $(cat build/err.txt)"
if $BIN load /nonexistent.dylib 2>build/err.txt; then fail "missing file should not load"; fi
grep -qi 'No file' build/err.txt || fail "expected not-found error, got: $(cat build/err.txt)"

section "trace"
$BIN trace "$FIX" --run '+[FXChild runSelfTest]' \
  '+[FXChild runSelfTest]' '-[FXBase greet:]' '-[FXChild addInt:toInt:]' '-[FXBase insetRect:by:]' \
  '-[FXBase vectorScaled:by:]' '-[FXBase rangeOf:]' '-[FXBase isEnabled:]' '-[FXBase echoSelector:]' \
  '-[FXBase echoClass:]' '-[FXBase cString:]' '-[FXBase performBlock:]' '-[FXBase scale:by:]' > build/trace.txt || fail "trace exited non-zero"
expect() { grep -qF -- "$1" build/trace.txt || fail "trace output missing: $1"; }
expect '+[FXChild runSelfTest] () -> 16'
expect '  -[FXBase greet:] <FXChild:'
expect '("world") -> "Hello, world"'
expect '-[FXChild addInt:toInt:] <FXChild:'
expect '(2, 3) -> 105'
expect '({{0, 0}, {100, 50}}, 5) -> {{5, 5}, {90, 40}}'
expect '({1, 2, 3}, 2) -> {2, 4, 6}'
expect '("fix") -> {0, 3}'
expect '(YES) -> YES'
expect '(@selector(noArgs)) -> @selector(noArgs)'
expect '(NSString) -> NSString'
expect '("hello") -> "hello"'
expect '(<block 0x'
expect '(1.5, 2) -> 3'
expect 'events: 12, dropped: 0'
n=$(grep -c '^#' build/trace.txt); [ "$n" -eq 12 ] || fail "expected 12 event lines, got $n"

section "trace restores originals"
# After untraceAll the same run must still work and produce no events.
$BIN trace "$FIX" --run '+[FXChild runSelfTest]' '-[FXBase noArgs]' > build/trace2.txt || fail "second trace exited non-zero"
grep -q 'events: 1,' build/trace2.txt || fail "expected exactly one noArgs event: $(tail -1 build/trace2.txt)"

section "blocklist"
if $BIN trace - --run '+[NSObject class]' '-[NSObject description]' 2>build/err.txt; then fail "NSObject should be refused"; fi
grep -qi 'root' build/err.txt || fail "expected root-class refusal, got: $(cat build/err.txt)"
if $BIN trace "$FIX" --run '+[FXChild runSelfTest]' '-[FXChild retain]' 2>build/err.txt; then fail "retain should be refused"; fi
grep -qi 'cannot be traced' build/err.txt || fail "expected selector refusal, got: $(cat build/err.txt)"

section "hierarchy conflict"
if $BIN trace "$FIX" --run '+[FXChild runSelfTest]' '-[FXBase noArgs]' '-[FXChild noArgs]' 2>build/err.txt; then fail "conflict should be refused"; fi
grep -qi 'already traced on superclass' build/err.txt || fail "expected conflict error, got: $(cat build/err.txt)"

section "inherited method traced on subclass only"
$BIN trace "$FIX" --run '+[FXChild runSelfTest]' '-[FXChild noArgs]' > build/trace3.txt || fail "inherited trace exited non-zero"
grep -qF -- '-[FXChild noArgs] <FXChild:' build/trace3.txt || fail "expected noArgs traced via FXChild: $(cat build/trace3.txt)"

section "call with typed arguments"
callcheck() { out=$($BIN call "$FIX" "$@" 2>&1) || fail "call $1 exited non-zero: $out"; grep -qF -- "$CALL_EXPECT" <<<"$out" || fail "call $1: expected '$CALL_EXPECT' in '$out'"; }
CALL_EXPECT='-> 105' callcheck '-[FXChild addInt:toInt:]' 2 3
CALL_EXPECT='-> {{5, 5}, {90, 40}}' callcheck '-[FXBase insetRect:by:]' '{0, 0, 100, 50}' 5
CALL_EXPECT='-> "Hello, world"' callcheck '-[FXBase greet:]' '"world"'
CALL_EXPECT='-> NSString' callcheck '-[FXBase echoClass:]' NSString
CALL_EXPECT='-> @selector(noArgs)' callcheck '-[FXBase echoSelector:]' noArgs
CALL_EXPECT='-> YES' callcheck '-[FXBase isEnabled:]' YES
CALL_EXPECT='-> 1099511627776' callcheck '-[FXBase big:]' 1099511627776
CALL_EXPECT='-> {2, 4, 6}' callcheck '-[FXBase vectorScaled:by:]' '{1, 2, 3}' 2
CALL_EXPECT='-> 16' callcheck '+[FXChild runSelfTest]'
CALL_EXPECT='-> "hello"' callcheck '-[FXBase cString:]' hello
if $BIN call "$FIX" '-[FXBase addInt:toInt:]' 2 2>build/err.txt; then fail "wrong arity should be refused"; fi
grep -q 'takes 2 argument' build/err.txt || fail "expected arity error, got: $(cat build/err.txt)"

if [ "$failures" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures FAILURE(S)" >&2
  exit 1
fi
