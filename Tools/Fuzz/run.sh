#!/usr/bin/env bash
# Builds the board-loader fuzzer and runs it for $1 seconds (default 60). Linux, Swift 6.
set -euo pipefail
cd "$(dirname "$0")/../.."
seconds="${1:-60}"
build="$(mktemp -d)"
swiftc -sanitize=fuzzer,address -parse-as-library -O -module-name BoardFuzz \
  $(find Packages/BoardKit/Sources -name '*.swift' | sort) Tools/Fuzz/BoardFuzz.swift \
  -o "$build/boardfuzz"
corpus="$build/corpus"
mkdir -p "$corpus" "$build/crashes"
cp Tools/Fuzz/corpus/* docs/examples/harbor-case.evboard "$corpus/"
export ASAN_OPTIONS="detect_leaks=0:${ASAN_OPTIONS:-}"
"$build/boardfuzz" -max_total_time="$seconds" -max_len=262144 -timeout=10 -rss_limit_mb=4096 \
  -dict=Tools/Fuzz/evboard.dict -artifact_prefix="$build/crashes/" -print_final_stats=1 "$corpus"
