`timescale 1ns/1ps

// ─────────────────────────────────────────────────────────────────────────────
// Integration testbench for mag_deck_core
// Exercises the full pipeline: buttons → debounce → input_mapper → tx_encoder → uart_tx
//
// HOW TO COMPILE AND RUN (from the mag_deck directory):
//   iverilog -g2012 -o core_sim.vvp \
//     testBenches/core_boot_tb.sv \
//     unit/mag_deck_core.sv unit/debounce.sv unit/i2c_master.sv \
//     unit/input_mapper.sv unit/tx_encoder.sv unit/uart_tx.sv
//   vvp core_sim.vvp
//   gtkwave core_boot.vcd
//
// WHAT TO LOOK FOR IN GTKWAVE:
//   dut.clean_face_btn     — settles after THRESHOLD cycles from stable press
//   dut.poll_tick          — pulses every 500K cycles (10 ms)
//   i2c_scl_1 / i2c_scl_2 — toggle after each poll_tick (masters start transaction)
//   tx_pin                 — UART frames appear after each poll_tick
//   dut.enc.state          — steps IDLE→START→WAIT×5→IDLE per packet
//   dut.uart.state         — steps IDLE→START→DATA→STOP per byte
// ─────────────────────────────────────────────────────────────────────────────

module core_boot_tb();

  // ── Parameters ────────────────────────────────────────────────────────────
  localparam CLK_FREQ        = 50_000_000;
  localparam BAUD_RATE       = 115_200;
  localparam DIVISOR         = CLK_FREQ / BAUD_RATE;  // 434 cycles per bit
  localparam HALF_BIT        = DIVISOR / 2;            // 217
  localparam DEBOUNCE_THRESH = 50_000;

  // ── Inputs ────────────────────────────────────────────────────────────────
  logic       clk        = 1'b0;
  logic       rst_n      = 1'b0;
  logic [3:0] face_btn   = 4'b0000;
  logic [3:0] dpad       = 4'b0000;
  logic [1:0] bumpers    = 2'b00;
  logic       start_btn  = 1'b0;
  logic       select_btn = 1'b0;

  // ── I2C ───────────────────────────────────────────────────────────────────
  // pullup models the physical pull-up resistors on the I2C bus.
  // No slave is modelled — masters will attempt transactions and see NACK.
  wire i2c_scl_1, i2c_scl_2;
  wire i2c_sda_1, i2c_sda_2;
  pullup pu1 (i2c_sda_1);
  pullup pu2 (i2c_sda_2);

  // ── UART output ───────────────────────────────────────────────────────────
  wire tx_pin;

  // ── DUT ───────────────────────────────────────────────────────────────────
  mag_deck_core dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .face_btn   (face_btn),
    .dpad       (dpad),
    .bumpers    (bumpers),
    .start_btn  (start_btn),
    .select_btn (select_btn),
    .i2c_scl_1  (i2c_scl_1),
    .i2c_sda_1  (i2c_sda_1),
    .i2c_scl_2  (i2c_scl_2),
    .i2c_sda_2  (i2c_sda_2),
    .tx_pin     (tx_pin)
  );

  // ── 50 MHz clock ──────────────────────────────────────────────────────────
  always #10 clk = ~clk;

  // ── Diagnostics ───────────────────────────────────────────────────────────
  always @(posedge dut.tx_start)
    $display("  DIAG  tx_start pulse: tx_byte=0x%02X  t=%0t", dut.tx_byte, $time);

  always @(negedge tx_pin)
    $display("  DIAG  tx_pin negedge  t=%0t", $time);

  // ── Task: capture one UART byte ───────────────────────────────────────────
  // Call immediately after @(negedge tx_pin) — enters at start of start bit.
  // Skips start bit, samples 8 data bits LSB-first at their midpoints,
  // then leaves sim position near midpoint of stop bit.
  task capture_uart_byte;
    output [7:0] captured;
    integer b;
    begin
      // Advance past start bit and to midpoint of bit 0
      repeat(DIVISOR + HALF_BIT) @(posedge clk); #1;
      // Sample 8 data bits, one bit period apart
      for (b = 0; b < 8; b = b + 1) begin
        captured[b] = tx_pin;
        repeat(DIVISOR) @(posedge clk); #1;
      end
      // Now near midpoint of stop bit — next @(negedge tx_pin) will sync to next byte
    end
  endtask

  // ── Task: PASS/FAIL check ─────────────────────────────────────────────────
  task check_byte;
    input [7:0]  got;
    input [7:0]  expected;
    input [79:0] label;
    begin
      if (got === expected)
        $display("  PASS  %s  0x%02X", label, got);
      else
        $display("  FAIL  %s  got 0x%02X  expected 0x%02X", label, got, expected);
    end
  endtask

  // ── Stimulus ──────────────────────────────────────────────────────────────
  logic [7:0] byte_cap;

  initial begin
    $dumpfile("core_boot.vcd");
    $dumpvars(0, core_boot_tb);

    // ── PHASE 1: Reset ────────────────────────────────────────────────────
    $display("\n── PHASE 1: Reset ──");
    rst_n = 1'b0;
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk); #1;
    if (tx_pin === 1'b1)
      $display("  PASS  tx_pin idle high after reset");
    else
      $display("  FAIL  tx_pin not high after reset");

    // ── PHASE 2: Bounce then stable inputs ───────────────────────────────
    // Bounce on face_btn[1]; stable inputs settle on face_btn[0] + others.
    // Expected packet values:
    //   pkt[1] = {4'b0, start=1, select=0, bumpers=01} = 0x05
    //   pkt[2] = {face_btn=0001, dpad=0001}             = 0x11
    $display("\n── PHASE 2: Bounce + stable inputs ──");
    @(posedge clk); face_btn[1] = 1'b1;
    @(posedge clk); face_btn[1] = 1'b0;
    @(posedge clk); face_btn[1] = 1'b1;
    @(posedge clk); face_btn[1] = 1'b0;
    @(posedge clk);
    face_btn  = 4'b0001;
    dpad      = 4'b0001;
    bumpers   = 2'b01;
    start_btn = 1'b1;
    $display("  Inputs: face=0001 dpad=0001 bumpers=01 start=1");

    // ── PHASE 3: Debounce settle ──────────────────────────────────────────
    $display("\n── PHASE 3: Debounce settle ──");
    repeat(DEBOUNCE_THRESH + 500) @(posedge clk); #1;
    if (dut.clean_face_btn === 4'b0001)
      $display("  PASS  clean_face_btn = 0001 (bounce filtered)");
    else
      $display("  FAIL  clean_face_btn = %b (expected 0001)", dut.clean_face_btn);
    if (dut.clean_start_btn === 1'b1)
      $display("  PASS  clean_start_btn = 1");
    else
      $display("  FAIL  clean_start_btn = %b", dut.clean_start_btn);

    // ── PHASE 4: Wait for poll_tick ───────────────────────────────────────
    // tx_pin goes low ~2 cycles after poll_tick — go straight to @(negedge)
    // with no added delay so we don't miss the first start bit.
    $display("\n── PHASE 4: Waiting for poll_tick ──");
    @(posedge dut.poll_tick);
    #1;
    $display("  poll_tick fired  pkt={0x%02X,0x%02X,0x%02X,0x%02X,0x%02X}",
             dut.pkt[0], dut.pkt[1], dut.pkt[2], dut.pkt[3], dut.pkt[4]);

    // ── PHASE 5: UART byte 0 — sync (0xAA) ───────────────────────────────
    $display("\n── PHASE 5: UART byte 0 (sync) ──");
    @(negedge tx_pin);
    capture_uart_byte(byte_cap);
    check_byte(byte_cap, 8'hAA, "byte[0] sync  ");

    // ── PHASE 6: UART byte 1 — buttons (0x09) ────────────────────────────
    $display("\n── PHASE 6: UART byte 1 (buttons) ──");
    @(negedge tx_pin);
    capture_uart_byte(byte_cap);
    check_byte(byte_cap, 8'h09, "byte[1] btns  ");

    // ── PHASE 7: UART byte 2 — face + dpad (0x11) ────────────────────────
    $display("\n── PHASE 7: UART byte 2 (face+dpad) ──");
    @(negedge tx_pin);
    capture_uart_byte(byte_cap);
    check_byte(byte_cap, 8'h11, "byte[2] f+d   ");

    // ── PHASE 8: UART bytes 3,4 — trackpad data ───────────────────────────
    // No I2C slave model — tp_data stays at 0x00 (reset value).
    $display("\n── PHASE 8: UART bytes 3,4 (trackpad, no slave) ──");
    @(negedge tx_pin);
    capture_uart_byte(byte_cap);
    $display("  byte[3] tp_data_1 = 0x%02X (no slave — expect 0x00)", byte_cap);

    @(negedge tx_pin);
    capture_uart_byte(byte_cap);
    $display("  byte[4] tp_data_2 = 0x%02X (no slave — expect 0x00)", byte_cap);

    // ── PHASE 9: I2C SCL activity ─────────────────────────────────────────
    // UART transmission just finished (~21K cycles since poll_tick).
    // I2C masters (100kHz, 500 cycles/bit) have had plenty of time to start.
    $display("\n── PHASE 9: I2C SCL activity ──");
    repeat(10) @(posedge clk); #1;
    $display("  i2c_scl_1 = %b  i2c_scl_2 = %b  (expect both toggling)", i2c_scl_1, i2c_scl_2);

    // ── PHASE 10: Pipeline idle check ────────────────────────────────────
    $display("\n── PHASE 10: Pipeline idle check ──");
    repeat(DIVISOR + 20) @(posedge clk); #1;
    if (dut.tx_busy === 1'b0)
      $display("  PASS  tx_busy low — pipeline in IDLE");
    else
      $display("  FAIL  tx_busy still high");
    if (tx_pin === 1'b1)
      $display("  PASS  tx_pin idle high");
    else
      $display("  FAIL  tx_pin not idle");

    // ── PHASE 11: Second packet on next poll_tick ─────────────────────────
    $display("\n── PHASE 11: Second packet ──");
    @(posedge dut.poll_tick);
    @(negedge tx_pin);
    capture_uart_byte(byte_cap);
    check_byte(byte_cap, 8'hAA, "byte[0] sync  ");
    $display("  (second packet confirmed firing on schedule)");

    $display("\n── Integration sim complete ──\n");
    $finish;
  end

endmodule
