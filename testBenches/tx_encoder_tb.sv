`timescale 1ns/1ps

// ─────────────────────────────────────────────────────────────────────────────
// Testbench for tx_encoder.sv
//
// This TB has to play the role of uart_tx — it drives tx_busy in response to
// tx_start pulses, holding the line busy for BUSY_CYCLES clocks to simulate
// a byte being serialised. The FSM is tested by watching it walk through all
// 5 packet bytes in order and return to IDLE.
//
// HOW TO COMPILE AND RUN (from the mag_deck directory):
//   iverilog -g2012 -o tx_encoder_tb.vvp testBenches/tx_encoder_tb.sv unit/tx_encoder.sv
//   vvp tx_encoder_tb.vvp
//   gtkwave tx_encoder_tb.vcd
//
// WHAT TO LOOK FOR IN GTKWAVE:
//   state        — should step IDLE→START→WAIT→START→...→IDLE across the packet
//   tx_start     — should pulse high for exactly one cycle per byte
//   tx_byte      — should show 0xAA, 0x0F, 0xA5, 0xDE, 0xAD in sequence
//   tx_busy      — driven by this TB; should go high shortly after each tx_start
//   byte_idx     — counts 0→1→2→3→4 then stops
// ─────────────────────────────────────────────────────────────────────────────

module tx_encoder_tb();

  // ── Inputs to DUT ─────────────────────────────────────────────────────────
  logic       clk       = 1'b0;
  logic       rst_n     = 1'b0;
  logic [7:0] pkt [0:4];
  logic       pkt_valid = 1'b0;
  logic       tx_busy   = 1'b0;   // driven by the uart_tx model below

  // ── Outputs from DUT ──────────────────────────────────────────────────────
  wire  [7:0] tx_byte;
  wire        tx_start;

  // ── DUT instantiation ─────────────────────────────────────────────────────
  tx_encoder dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .pkt      (pkt),
    .pkt_valid(pkt_valid),
    .tx_byte  (tx_byte),
    .tx_start (tx_start),
    .tx_busy  (tx_busy)
  );

  // ── 50 MHz clock ──────────────────────────────────────────────────────────
  always #10 clk = ~clk;

  // ── uart_tx model: raise tx_busy on tx_start, hold for BUSY_CYCLES ────────
  //
  // Real uart_tx would take ~4340 cycles at 115200 baud / 50 MHz.
  // Using 10 cycles here — enough to exercise the WAIT logic without a long sim.
  localparam BUSY_CYCLES = 10;
  logic [3:0] busy_cnt = '0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_busy  <= 1'b0;
      busy_cnt <= '0;
    end else if (tx_start && !tx_busy) begin
      // tx_start fired — go busy and start counting
      tx_busy  <= 1'b1;
      busy_cnt <= '0;
    end else if (tx_busy) begin
      if (busy_cnt == BUSY_CYCLES - 1)
        tx_busy <= 1'b0;          // transmission done, release the line
      else
        busy_cnt <= busy_cnt + 1'b1;
    end
  end

  // ── Helper task ───────────────────────────────────────────────────────────
  task check_byte;
    input [7:0]  got;
    input [7:0]  expected;
    input [47:0] label;
    begin
      if (got === expected)
        $display("  PASS  %s  got 0x%02X", label, got);
      else
        $display("  FAIL  %s  got 0x%02X  expected 0x%02X", label, got, expected);
    end
  endtask

  // ── Stimulus ──────────────────────────────────────────────────────────────
  initial begin
    $dumpfile("tx_encoder_tb.vcd");
    $dumpvars(0, tx_encoder_tb);

    // Load a packet — same values used in input_mapper_tb so you can recognise them
    pkt[0] = 8'hAA;   // sync
    pkt[1] = 8'h0F;   // start+select+both bumpers
    pkt[2] = 8'hA5;   // face_btn=1010, dpad=0101
    pkt[3] = 8'hDE;
    pkt[4] = 8'hAD;

    // Reset
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    // Fire pkt_valid for one cycle to trigger the FSM
    @(posedge clk);
    pkt_valid = 1'b1;
    @(posedge clk);
    pkt_valid = 1'b0;

    // ── Watch all 5 bytes go out ──────────────────────────────────────────
    //
    // Each tx_start pulse marks the moment a byte is handed to uart_tx.
    // We sample tx_byte on that same cycle and compare to the expected sequence.
    // @(posedge tx_start) suspends here until the DUT fires the pulse — just
    // like @(posedge rx_valid) in i2c_master_tb.

    $display("\n── Byte sequence ──");

    @(posedge tx_start); #1;
    check_byte(tx_byte, 8'hAA, "byte[0]");

    @(posedge tx_start); #1;
    check_byte(tx_byte, 8'h0F, "byte[1]");

    @(posedge tx_start); #1;
    check_byte(tx_byte, 8'hA5, "byte[2]");

    @(posedge tx_start); #1;
    check_byte(tx_byte, 8'hDE, "byte[3]");

    @(posedge tx_start); #1;
    check_byte(tx_byte, 8'hAD, "byte[4]");

    // ── Confirm FSM returns to IDLE ───────────────────────────────────────
    // After the last byte, give the uart_tx model time to finish, then check
    // that tx_start stays low — the FSM should be back in IDLE, not looping.
    repeat(BUSY_CYCLES + 5) @(posedge clk);
    #1;
    $display("\n── IDLE check ──");
    if (tx_start === 1'b0)
      $display("  PASS  tx_start low after packet complete — FSM in IDLE");
    else
      $display("  FAIL  tx_start still high — FSM did not return to IDLE");

    $display("\nDone.\n");
    $finish;
  end

endmodule
