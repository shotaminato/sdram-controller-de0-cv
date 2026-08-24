#!/usr/bin/env bash
# Run the same testbench against Verilog and SystemVerilog controllers
# and compare per-cycle pin dumps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TB="$ROOT/tb"
RTL="$ROOT/rtl"
OUT="$TB/out"
mkdir -p "$OUT"

if ! command -v iverilog >/dev/null || ! command -v vvp >/dev/null; then
  echo "FAIL: iverilog/vvp not found"
  exit 1
fi

echo "== Verilog controller =="
iverilog -g2012 -o "$OUT/sim_v.vvp" \
  "$RTL/sdram_controller.v" \
  "$TB/sdram_model.v" \
  "$TB/sdram_controller_tb.v"
vvp "$OUT/sim_v.vvp" "+LOG=$OUT/v.log" | tee "$OUT/v_run.txt"

echo "== SystemVerilog controller =="
iverilog -g2012 -I "$RTL" -o "$OUT/sim_sv.vvp" \
  "$RTL/dff.sv" \
  "$RTL/sdram_controller.sv" \
  "$TB/sdram_model.v" \
  "$TB/sdram_controller_tb.v"
vvp "$OUT/sim_sv.vvp" "+LOG=$OUT/sv.log" | tee "$OUT/sv_run.txt"

if grep -q '^FAIL' "$OUT/v_run.txt" || grep -q '^FAIL' "$OUT/sv_run.txt"; then
  echo "FAIL: a controller self-check failed"
  exit 1
fi

if ! grep -q '^PASS: sdram_controller_tb' "$OUT/v_run.txt"; then
  echo "FAIL: Verilog run did not report PASS"
  exit 1
fi
if ! grep -q '^PASS: sdram_controller_tb' "$OUT/sv_run.txt"; then
  echo "FAIL: SystemVerilog run did not report PASS"
  exit 1
fi

echo "== Compare pin dumps =="
if [[ ! -s "$OUT/v.log" || ! -s "$OUT/sv.log" ]]; then
  echo "FAIL: empty pin dump"
  exit 1
fi
if ! diff -u "$OUT/v.log" "$OUT/sv.log"; then
  echo "FAIL: Verilog and SystemVerilog pin traces differ"
  exit 1
fi

echo "PASS: Verilog and SystemVerilog controllers match"
