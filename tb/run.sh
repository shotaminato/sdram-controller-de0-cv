#!/usr/bin/env bash
# Self-checking simulation of the SystemVerilog sdram_controller.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/tb/out"
mkdir -p "$OUT"

if ! command -v iverilog >/dev/null || ! command -v vvp >/dev/null; then
  echo "FAIL: iverilog/vvp not found"
  exit 1
fi
if ! command -v bender >/dev/null; then
  echo "FAIL: bender not found"
  exit 1
fi

mapfile -t SV_SRCS < <(cd "$ROOT" && bender script flist -t test)
iverilog -g2012 -o "$OUT/sim.vvp" "${SV_SRCS[@]}"
vvp "$OUT/sim.vvp"
