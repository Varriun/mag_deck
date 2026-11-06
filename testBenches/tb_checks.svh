// ─────────────────────────────────────────────────────────────────────────────
// tb_checks.svh — shared self-checking scoreboard for mag_deck testbenches
//
// USAGE (inside the testbench module, after the clock/DUT declarations):
//
//   localparam string TB_NAME    = "uart_tx_tb";
//   localparam int    TIMEOUT_NS = 1_000_000;    // hard limit for the whole run
//   `include "testBenches/tb_checks.svh"
//
//   ...
//   check(sig === 1'b1, "description");          // any condition
//   check_byte(got, 8'hAA, "pkt[0]");            // byte compare with hex print
//   ...
//   report_and_finish();                          // last line of the stimulus
//
// Compile from the repo root (the include path is relative to it).
//
// DESIGN NOTES
//   * All counting happens inside check(), so a check can never be added
//     without being counted — and nothing else touches the counters.
//   * Build conditions with === / !== so X or Z can never count as a pass.
//   * report_and_finish() ends with $fatal(1, ...) on failure, which makes
//     vvp exit with status 1 (scripts/CI can see it). $finish(n) would NOT:
//     its argument only sets how much it prints; exit status stays 0.
//   * A run with zero checks is a FAIL, not a vacuous pass.
//   * The watchdog turns "a wait never completed" (hang) into a counted
//     failure instead of a sim that runs forever or ends looking clean.
// ─────────────────────────────────────────────────────────────────────────────

  int checkCnt = 0;
  int errCnt   = 0;

  // ── Generic check ─────────────────────────────────────────────────────────
  task automatic check(input bit ok, input string msg);
    checkCnt++;
    if (ok) begin
      $display("  PASS  %s", msg);
    end else begin
      errCnt++;
      $display("  FAIL  %s  (t=%0t)", msg, $time);
    end
  endtask

  // ── Byte compare ──────────────────────────────────────────────────────────
  task automatic check_byte(input logic [7:0] got, input logic [7:0] expected,
                            input string label);
    check(got === expected,
          $sformatf("%s got 0x%02X  expected 0x%02X", label, got, expected));
  endtask

  // ── Final verdict + exit status ───────────────────────────────────────────
  task automatic report_and_finish();
    $display("\n══════════════════════════════════════════");
    $display("  %s", TB_NAME);
    $display("  CHECKS: %0d   PASS: %0d   FAIL: %0d",
             checkCnt, checkCnt - errCnt, errCnt);
    if (errCnt == 0 && checkCnt > 0) begin
      $display("  TEST PASSED");
      $display("══════════════════════════════════════════\n");
      $finish;
    end else begin
      $display("  TEST FAILED");
      $display("══════════════════════════════════════════\n");
      $fatal(1, "%s: %0d of %0d checks failed", TB_NAME, errCnt, checkCnt);
    end
  endtask

  // ── Watchdog ──────────────────────────────────────────────────────────────
  // In a passing run, report_and_finish() ends the sim before this fires.
  initial begin
    #(TIMEOUT_NS);
    check(1'b0, $sformatf("watchdog: sim exceeded %0d ns — a wait never completed",TIMEOUT_NS));
    report_and_finish();
  end
