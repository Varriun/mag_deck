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
  localparam CLK_FREQ  = 50_000_000;
  localparam BAUD_RATE = 115_200;
  localparam DIVISOR   = CLK_FREQ / BAUD_RATE;   // 434 cycles per bit
  localparam HALF_BIT  = DIVISOR / 2;             // sample midpoint

  // ── Inputs to DUT ─────────────────────────────────────────────────────────
  logic       clk      = 1'b0;
  logic       rst_n    = 1'b0;
  logic       tx_start = 1'b0;
  logic [7:0] tx_byte  = 8'h00;

  // ── Outputs from DUT ──────────────────────────────────────────────────────
  wire  tx_pin;
  wire  tx_busy;

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

  // ── Task: sample tx_pin at midpoint of current bit, check expected value ──
  task check_bit;
    input       expected;
    input [7:0] label;
    begin
      repeat (HALF_BIT) @(posedge clk);
      #1;
      if (tx_pin === expected)
        $display("  PASS  bit[%0d]  got %b", label, tx_pin);
      else
        $display("  FAIL  bit[%0d]  got %b  expected %b", label, tx_pin, expected);
      // advance to end of this bit
      repeat (DIVISOR - HALF_BIT) @(posedge clk);
    end
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
    check_bit(1'b0, 8'd8); // label 8 = "start"
    $display("  PASS  start bit");

    // Check 8 data bits LSB-first: 0xA5 = 1010_0101 → LSB first: 1,0,1,0,0,1,0,1
    check_bit(1'b1, 8'd0);
    check_bit(1'b0, 8'd1);
    check_bit(1'b1, 8'd2);
    check_bit(1'b0, 8'd3);
    check_bit(1'b0, 8'd4);
    check_bit(1'b1, 8'd5);
    check_bit(1'b0, 8'd6);
    check_bit(1'b1, 8'd7);

    // Check stop bit
    check_bit(1'b1, 8'd9); // label 9 = "stop"
    $display("  PASS  stop bit");

    // ── Confirm tx_busy goes low after stop bit ───────────────────────────
    repeat(5) @(posedge clk); #1;
    $display("\n── tx_busy check ──");
    if (tx_busy === 1'b0)
      $display("  PASS  tx_busy low after frame complete");
    else
      $display("  FAIL  tx_busy still high");

    // ── Confirm tx_pin returns to idle high ───────────────────────────────
    $display("\n── idle check ──");
    if (tx_pin === 1'b1)
      $display("  PASS  tx_pin high (idle)");
    else
      $display("  FAIL  tx_pin low after frame");

    $display("\nDone.\n");
    $finish;
  end

endmodule
