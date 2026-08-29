#!/usr/bin/env bash
# Self-checking simulation of the SystemVerilog sdram_controller (Verilator).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tb/verilator/out"
PRIM_ROOT="${PRIM_ROOT:-$ROOT/deps/rtl_primitive}"
mkdir -p "$OUT"

if [[ ! -d "$PRIM_ROOT/pkg" ]]; then
  echo "FAIL: missing $PRIM_ROOT; run bender update"
  exit 1
fi

if verilator --version >/dev/null 2>&1; then
  VERILATOR=(verilator)
elif command -v verilator_bin >/dev/null; then
  VERILATOR=(verilator_bin)
  if [[ -z "${VERILATOR_ROOT:-}" ]]; then
    _vb="$(command -v verilator_bin)"
    export VERILATOR_ROOT="$(cd "$(dirname "$_vb")/../share/verilator" && pwd)"
  fi
else
  echo "FAIL: verilator not found"
  exit 1
fi

"${VERILATOR[@]}" --binary --timing -j 0 \
  --top-module sdram_controller_tb \
  -Wno-WIDTHEXPAND \
  -CFLAGS -O2 \
  -Mdir "$OUT/obj_dir" \
  -o sim \
  -I"$PRIM_ROOT/pkg" \
  -I"$ROOT/rtl" \
  -I"$ROOT/tb/verilator" \
  "$ROOT/tb/verilator/verilator_top.sv"

"$OUT/obj_dir/sim" "$@"
