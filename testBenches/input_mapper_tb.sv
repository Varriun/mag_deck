`timescale 1ns/1ps

// ─────────────────────────────────────────────────────────────────────────────
// Testbench for input_mapper.sv
//
// Three checks:
//   1. All-zeros: every data byte should be 0x00; pkt[0] always 0xAA.
//   2. Known pattern: drive recognisable values, verify each byte by hand.
//   3. pkt_valid strobe: assert poll_tick for one cycle, confirm pkt_valid
//      goes high for exactly that cycle then returns to 0.
//
// HOW TO COMPILE AND RUN (from the mag_deck directory):
//   iverilog -g2012 -o input_mapper_tb.vvp testBenches/input_mapper_tb.sv unit/input_mapper.sv
//   vvp input_mapper_tb.vvp
//   gtkwave input_mapper_tb.vcd
//
// WHAT TO LOOK FOR IN GTKWAVE:
//   pkt[0]     — should always be 0xAA
//   pkt[1]     — spare[3:0] | start | select | bumpers[1:0]
//   pkt[2]     — face_btn[3:0] | dpad[3:0]
//   pkt[3/4]   — raw trackpad bytes
//   pkt_valid  — one-cycle pulse aligned with poll_tick
// ─────────────────────────────────────────────────────────────────────────────

module input_mapper_tb();

  // ── Inputs to DUT ─────────────────────────────────────────────────────────
  logic       clk        = 1'b0;
  logic       rst_n      = 1'b0;
  logic [3:0] face_btn   = 4'b0;
  logic [3:0] dpad       = 4'b0;
  logic [1:0] bumpers    = 2'b0;
  logic       start_btn  = 1'b0;
  logic       select_btn = 1'b0;
  logic [7:0] tp_data_1  = 8'h00;
  logic [7:0] tp_data_2  = 8'h00;
  logic       poll_tick  = 1'b0;

  // ── Outputs from DUT ──────────────────────────────────────────────────────
  wire [7:0] pkt [0:4];
  wire       pkt_valid;

  // ── DUT instantiation ─────────────────────────────────────────────────────
  input_mapper dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .face_btn   (face_btn),
    .dpad       (dpad),
    .bumpers    (bumpers),
    .start_btn  (start_btn),
    .select_btn (select_btn),
    .tp_data_1  (tp_data_1),
    .tp_data_2  (tp_data_2),
    .poll_tick  (poll_tick),
    .pkt        (pkt),
    .pkt_valid  (pkt_valid)
  );

  // ── 50 MHz clock (20 ns period) ───────────────────────────────────────────
  always #10 clk = ~clk;

  // ── Helper task: check one byte ───────────────────────────────────────────
  task check_byte;
    input [7:0]  got;
    input [7:0]  expected;
    input [47:0] label;   // 6-char packed string, e.g. "pkt[0]"
    begin
      if (got === expected)
        $display("  PASS  %s  got 0x%02X", label, got);
      else
        $display("  FAIL  %s  got 0x%02X  expected 0x%02X", label, got, expected);
    end
  endtask

  // ── Stimulus ──────────────────────────────────────────────────────────────
  initial begin
    $dumpfile("input_mapper_tb.vcd");
    $dumpvars(0, input_mapper_tb);

    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    // ── Check 1: All-zeros ────────────────────────────────────────────────
    // pkt is combinational — outputs are valid immediately after inputs settle.
    #1;
    $display("\n── Check 1: all-zeros ──");
    check_byte(pkt[0], 8'hAA, "pkt[0]");
    check_byte(pkt[1], 8'h00, "pkt[1]");
    check_byte(pkt[2], 8'h00, "pkt[2]");
    check_byte(pkt[3], 8'h00, "pkt[3]");
    check_byte(pkt[4], 8'h00, "pkt[4]");

    // ── Check 2: Known pattern ────────────────────────────────────────────
    //
    // Drive recognisable values so you can verify the packing by hand:
    //   face_btn  = 4'b1010  (A and X pressed)
    //   dpad      = 4'b0101  (down and right)
    //   bumpers   = 2'b10    (L1 pressed, R1 not)
    //   start_btn = 1,  select_btn = 0
    //   tp_data_1 = 0xDE,  tp_data_2 = 0xAD
    //
    // Work out the expected bytes yourself before looking at the checks:
    //   pkt[1] = {4'b0000, start, select, bumpers} = ?
    //   pkt[2] = {face_btn, dpad}                  = ?

    face_btn   = 4'b1010;
    dpad       = 4'b0101;
    bumpers    = 2'b10;
    start_btn  = 1'b1;
    select_btn = 1'b0;
    tp_data_1  = 8'hDE;
    tp_data_2  = 8'hAD;
    #1;

    $display("\n── Check 2: known pattern ──");
    check_byte(pkt[0], 8'hAA, "pkt[0]");  // sync never changes
    check_byte(pkt[1], 8'h0A, "pkt[1]");  // 0000 | 1 | 0 | 10  = 0x0A
    check_byte(pkt[2], 8'hA5, "pkt[2]");  // 1010 | 0101        = 0xA5
    check_byte(pkt[3], 8'hDE, "pkt[3]");
    check_byte(pkt[4], 8'hAD, "pkt[4]");

    // ── Check 3: pkt_valid strobe ─────────────────────────────────────────
    // Assert poll_tick for exactly one clock cycle.
    // pkt_valid must go high on that same cycle, then return to 0.

    $display("\n── Check 3: pkt_valid strobe ──");
    @(posedge clk);
    poll_tick = 1'b1;
    @(posedge clk);
    #1;
    if (pkt_valid === 1'b1)
      $display("  PASS  pkt_valid high while poll_tick asserted");
    else
      $display("  FAIL  pkt_valid did not go high with poll_tick");

    poll_tick = 1'b0;
    @(posedge clk);
    #1;
    if (pkt_valid === 1'b0)
      $display("  PASS  pkt_valid returned low after poll_tick released");
    else
      $display("  FAIL  pkt_valid stuck high");

    $display("\nDone.\n");
    $finish;
  end

endmodule
