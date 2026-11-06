`default_nettype none
// Testbench-only: plain `always` (clock/monitors) and `===` (X-aware checks)
// are correct here; these two rules target synthesizable RTL.
/* svlint off keyword_forbidden_always */
/* svlint off operator_case_equality */
`timescale 1ns/1ps

// ─────────────────────────────────────────────────────────────────────────────
// Testbench for uart_tx.sv
//
// Plays the role of tx_encoder: drives tx_start + tx_byte, then verifies the
// UART frame that comes out on tx_pin.
//
// HOW TO COMPILE AND RUN (from the mag_deck directory):
//   iverilog -g2012 -o uart_sim.vvp testBenches/uart_tx_tb.sv unit/uart_tx.sv
//   vvp uart_sim.vvp
//   gtkwave uart_tx_tb.vcd
//
// WHAT TO LOOK FOR IN GTKWAVE:
//   tx_pin   — should show: 1 (idle) → 0 (start) → 8 data bits → 1 (stop) → 1 (idle)
//   tx_busy  — goes high on tx_start pulse, low after stop bit
//   state    — steps IDLE→START→DATA→STOP→IDLE
// ─────────────────────────────────────────────────────────────────────────────

module uart_tx_tb();

  // ── Parameters ────────────────────────────────────────────────────────────
  localparam int CLK_FREQ  = 50_000_000;
  localparam int BAUD_RATE = 115_200;
  localparam int DIVISOR   = CLK_FREQ / BAUD_RATE;   // 434 cycles per bit
  localparam int HALF_BIT  = DIVISOR / 2;             // sample midpoint

  // ── Inputs to DUT ─────────────────────────────────────────────────────────
  logic       clk      = 1'b0;
  logic       rst_n    = 1'b0;
  logic       tx_start = 1'b0;
  logic [7:0] tx_byte  = 8'h00;

  // ── Outputs from DUT ──────────────────────────────────────────────────────
  logic tx_pin;
  logic tx_busy;

  // ── DUT instantiation ─────────────────────────────────────────────────────
  uart_tx dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .tx_start (tx_start),
    .tx_byte  (tx_byte),
    .tx_pin   (tx_pin),
    .tx_busy  (tx_busy)
  );

  // ── 50 MHz clock (period = 20 ns) ─────────────────────────────────────────
  always #10 clk = ~clk;

  // ── Task: wait N bit periods (in clock cycles) ────────────────────────────
  task wait_bits;
    input integer n;
    repeat (n * DIVISOR) @(posedge clk);
  endtask

  // ── Scoreboard: check()/check_byte()/report_and_finish() + watchdog ──────
  // One frame is ~87 us; the watchdog fails the test at 1 ms.
  localparam string TB_NAME    = "uart_tx_tb";
  localparam int    TIMEOUT_NS = 1_000_000;
`include "testBenches/tb_checks.svh"

  // ── Task: sample tx_pin at midpoint of current bit, check expected value ──
  task automatic check_bit(input logic expected, input string label);
    repeat (HALF_BIT) @(posedge clk);
    #1;
    check(tx_pin === expected,
          $sformatf("%-6s got %b  expected %b", label, tx_pin, expected));
    // advance to end of this bit
    repeat (DIVISOR - HALF_BIT) @(posedge clk);
  endtask

  // ── Stimulus ──────────────────────────────────────────────────────────────
  initial begin
    $dumpfile("uart_tx_tb.vcd");
    $dumpvars(0, uart_tx_tb);

    // Reset
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    // ── Send 0xA5 = 8'b1010_0101 ─────────────────────────────────────────
    // LSB-first bit order: 1,0,1,0,0,1,0,1
    tx_byte  = 8'hA5;
    @(posedge clk);
    tx_start = 1'b1;
    @(posedge clk);
    tx_start = 1'b0;

    $display("\n── UART frame for 0xA5 ──");

    // Wait for start bit (tx_pin goes low)
    @(negedge tx_pin);

    // Check start bit
    check_bit(1'b0, "start");

    // Check 8 data bits LSB-first: 0xA5 = 1010_0101 → LSB first: 1,0,1,0,0,1,0,1
    check_bit(1'b1, "bit0");
    check_bit(1'b0, "bit1");
    check_bit(1'b1, "bit2");
    check_bit(1'b0, "bit3");
    check_bit(1'b0, "bit4");
    check_bit(1'b1, "bit5");
    check_bit(1'b0, "bit6");
    check_bit(1'b1, "bit7");

    // Check stop bit
    check_bit(1'b1, "stop");

    // ── Confirm tx_busy goes low after stop bit ───────────────────────────
    repeat(5) @(posedge clk); #1;
    $display("\n── tx_busy check ──");
    check(tx_busy === 1'b0, "tx_busy low after frame complete");

    // ── Confirm tx_pin returns to idle high ───────────────────────────────
    $display("\n── idle check ──");
    check(tx_pin === 1'b1, "tx_pin high (idle) after frame");

    report_and_finish();
  end

endmodule

`default_nettype wire
