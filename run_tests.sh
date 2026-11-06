#!/usr/bin/env bash
# Run every self-checking testbench; exit non-zero if any fails.
# Usage (from anywhere):  ./run_tests.sh        — or —  ./run_tests.sh uart_tx
set -u
cd "$(dirname "$0")"

# testbench name : RTL files it needs
declare -A TESTS=(
  [core_boot]="unit/mag_deck_core.sv unit/debounce.sv unit/i2c_master.sv unit/input_mapper.sv unit/tx_encoder.sv unit/uart_tx.sv"
  [i2c_master]="unit/i2c_master.sv"
  [uart_tx]="unit/uart_tx.sv"
  [tx_encoder]="unit/tx_encoder.sv"
  [input_mapper]="unit/input_mapper.sv"
)
ORDER=(input_mapper tx_encoder uart_tx i2c_master core_boot)
[ $# -gt 0 ] && ORDER=("$@")

failed=()
for t in "${ORDER[@]}"; do
  echo "── ${t}_tb"
  # shellcheck disable=SC2086
  if ! iverilog -g2012 -o "${t}.vvp" "testBenches/${t}_tb.sv" ${TESTS[$t]}; then
    echo "  COMPILE ERROR"; failed+=("$t"); continue
  fi
  log=$(vvp -n "${t}.vvp" 2>&1); rc=$?
  grep -E '  FAIL|CHECKS|TEST (PASSED|FAILED)' <<<"$log"
  [ $rc -eq 0 ] || failed+=("$t")
done

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "ALL ${#ORDER[@]} TESTBENCHES PASSED"
else
  echo "FAILED: ${failed[*]}"; exit 1
fi
