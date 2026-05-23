`timescale 1ns/1ps

// ─────────────────────────────────────────────────────────────────────────────
// Testbench for i2c_master.sv
//
// Runs one full I2C register-read transaction and checks the received byte.
//
// HOW TO COMPILE AND RUN (from the mag_deck directory):
//   iverilog -g2012 -o i2c_master_tb.vvp testBenches/i2c_master_tb.sv unit/i2c_master.sv
//   vvp i2c_master_tb.vvp
//   gtkwave i2c_master_tb.vcd
//
// WHAT TO LOOK FOR IN GTKWAVE:
//   Add these signals to the wave view (they are inside dut.*):
//     i2c_scl, i2c_sda         -- the actual bus lines
//     dut.state                 -- FSM state cycling START->ADDR_W->...->STOP
//     dut.phase                 -- 0/1/2/3 sub-phases within each bit period
//     dut.bit_cnt               -- counts 7 down to 0 within each byte
//     dut.shift_reg             -- byte being clocked out
//     dut.rx_buf                -- byte being assembled during READ
//     rx_valid, rx_data         -- pulses + final result
// ─────────────────────────────────────────────────────────────────────────────

module i2c_master_tb();

  // ── Inputs to DUT ─────────────────────────────────────────────────────────
  logic       clk     = 1'b0;
  logic       rst_n;
  logic       start;
  logic [6:0] dev_addr;
  logic [7:0] reg_addr;

  // ── Outputs from DUT ──────────────────────────────────────────────────────
  wire  [7:0] rx_data;
  wire        rx_valid;
  wire        i2c_scl;

  // ── Shared open-drain SDA bus ─────────────────────────────────────────────
  // Both the DUT and the target model pull SDA low or release it.
  // The wire resolves: if either drives low, bus is low.
  wire        i2c_sda;

  logic tgt_sda_out = 1'b1;
  logic tgt_sda_oe  = 1'b0;
  assign i2c_sda = (tgt_sda_oe && !tgt_sda_out) ? 1'b0 : 1'bz;

  // ── DUT instantiation ─────────────────────────────────────────────────────
  i2c_master dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .start    (start),
    .dev_addr (dev_addr),
    .reg_addr (reg_addr),
    .rx_data  (rx_data),
    .rx_valid (rx_valid),
    .i2c_scl  (i2c_scl),
    .i2c_sda  (i2c_sda)
  );

  // ── 50 MHz clock (20 ns period) ───────────────────────────────────────────
  always #10 clk = ~clk;

  // ── Stimulus ──────────────────────────────────────────────────────────────
  initial begin
    $dumpfile("i2c_master_tb.vcd");
    $dumpvars(0, i2c_master_tb);   // depth 0 = capture DUT internals too

    dev_addr = 7'h2A;              // Cirque trackpad default I2C address
    reg_addr = 8'h14;              // absolute X-position register
    start    = 1'b0;
    rst_n    = 1'b0;

    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(2)  @(posedge clk);

    // One-cycle pulse triggers the full transaction
    @(posedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    // Wait for master to finish and pulse rx_valid
    @(posedge rx_valid);
    repeat(20) @(posedge clk);

    $display("rx_data = 0x%02X (expected 0xA5)", rx_data);
    if (rx_data === 8'hA5)
      $display("PASS: received correct data byte.");
    else
      $display("FAIL: data mismatch.");

    $finish;
  end

  // ── Target (device) model ─────────────────────────────────────────────────
  // Behaves as a Cirque-style trackpad at address 0x2A.
  // Does not validate the address or register — just counts bit-clocks
  // and responds at the right moments.
  // Returns data byte 0xA5 (1010_0101) during the READ phase.
  //
  // Style: event-driven using @(posedge/negedge) — each line reads as a
  // step in the I2C protocol spec, which makes the timing self-documenting.
  //
  // ACK pattern for each of the three ACK slots:
  //   1. Wait for the 8th data posedge (last bit sampled by master).
  //   2. On the next SCL negedge: drive SDA low (ACK setup).
  //   3. On the next SCL posedge: master samples ACK = 0. Good.
  //   4. On the next SCL negedge: release SDA (ACK clock ends).

  logic [7:0] tgt_data = 8'hA5;

  initial begin
    tgt_sda_oe  = 1'b0;
    tgt_sda_out = 1'b1;

    // ── 1. Wait for START condition ───────────────────────────────────────
    // START = SDA falls while SCL is high.
    @(negedge i2c_sda);              // SDA falls = START seen

    // ── 2. Receive address + WRITE bit (8 SCL clocks) ────────────────────
    repeat(8) @(posedge i2c_scl);

    // ── 3. ACK the address + WRITE ────────────────────────────────────────
    @(negedge i2c_scl);              // SCL falls after bit 0
    tgt_sda_oe  = 1'b1;
    tgt_sda_out = 1'b0;              // pull SDA low = ACK
    @(posedge i2c_scl);              // ACK SCL rises (master samples ACK here)
    @(negedge i2c_scl);              // ACK SCL falls
    tgt_sda_oe  = 1'b0;              // release SDA

    // ── 4. Receive register address byte (8 SCL clocks) ──────────────────
    repeat(8) @(posedge i2c_scl);

    // ── 5. ACK the register address ───────────────────────────────────────
    @(negedge i2c_scl);
    tgt_sda_oe  = 1'b1;
    tgt_sda_out = 1'b0;
    @(posedge i2c_scl);
    @(negedge i2c_scl);
    tgt_sda_oe  = 1'b0;              // release before RSTART

    // ── 6. Wait for REPEATED START ────────────────────────────────────────
    // Master releases SDA (goes high via pull-up), then re-asserts START.
    // SDA falling while SCL is high = REPEATED START.
    @(negedge i2c_sda);              // SDA falls = REPEATED START seen

    // ── 7. Receive address + READ bit (8 SCL clocks) ─────────────────────
    repeat(8) @(posedge i2c_scl);

    // ── 8. ACK the address + READ, then stream data bits ─────────────────
    // We keep tgt_sda_oe = 1 through the entire READ phase.
    // On each SCL falling edge: place the next data bit on SDA.
    // On each SCL rising edge:  the master samples SDA.
    @(negedge i2c_scl);              // SCL falls after ADDR_R bit 0
    tgt_sda_oe  = 1'b1;
    tgt_sda_out = 1'b0;              // ACK
    @(posedge i2c_scl);              // ACK SCL rises (master samples ACK)

    // Drive 0xA5 = 1010_0101, MSB first
    // The ACK SCL falling edge also serves as the setup edge for bit 7.
    for (int i = 7; i >= 0; i = i - 1) begin
      @(negedge i2c_scl);            // SCL falls = time to place bit on SDA
      tgt_sda_out = tgt_data[i];     // bit 7 first, bit 0 last
      @(posedge i2c_scl);            // SCL rises = master samples this bit
    end

    // ── 9. Release after NACK ─────────────────────────────────────────────
    // Master holds SDA high for one bit-period (NACK).
    // We release our drive so we do not fight the master.
    @(negedge i2c_scl);              // SCL falls after last data bit
    tgt_sda_oe  = 1'b0;
  end

endmodule
