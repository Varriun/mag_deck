module mag_deck_core (
  input logic clk,
  input logic rst_n,

  // Digital Inputs (Buttons)
  input logic [3:0] face_btn,   // A,B,X,Y
  input logic [3:0] dpad,       // U,D,L,R
  input logic [1:0] bumpers,    // L1,R1
  input logic start_btn,
  input logic select_btn,

  // Analog Trackpad Interface (external ADC)
  // 1st Trackpad Interface (I2C)
  output logic i2c_scl_1,
  inout  wire  i2c_sda_1,
  
  //2nd Trackpad interface
  //note: maybe I should give slightly different names like i2c_scl_2?
  output logic i2c_scl_2,
  inout  wire  i2c_sda_2,

  // Output to phone
  output logic tx_pin
);

  // ── Debounced (clean) signals ──────────────────────────────────
  logic [3:0] clean_face_btn;
  logic [3:0] clean_dpad;
  logic [1:0] clean_bumper;
  logic       clean_start_btn;
  logic       clean_select_btn;

  // Note: analog sticks are not debounced — ADC outputs are
  // already filtered upstream and change continuously.

  // ── Debounce instances ─────────────────────────────────────────
  // face_btn[3:0] — 4 instances via generate
  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : gen_face_db
      debounce #(.THRESHOLD(50000)) db_face (
        .clk   (clk),
        .rst_n (rst_n),
        .sw_in (face_btn[i]),
        .sw_out(clean_face_btn[i])
      );
    end
  endgenerate

  // dpad[3:0] — 4 instances
  generate 
    for (i = 0; i < 4; i = i + 1) begin : gen_dpad_db
      debounce #(.THRESHOLD(50000)) db_dpad (
        .clk   (clk),
        .rst_n (rst_n),
        .sw_in (dpad[i]),
        .sw_out(clean_dpad[i])
      );
    end
  endgenerate

  // bumpers[1:0] — 2 instances
  generate
    for (i = 0; i < 2; i = i + 1) begin : gen_bumper_db
      debounce #(.THRESHOLD(50000)) db_bumper (
        .clk   (clk),
        .rst_n (rst_n),
        .sw_in (bumpers[i]),
        .sw_out(clean_bumper[i])
      );
    end
  endgenerate

  // start_btn — single instance
  debounce #(.THRESHOLD(50000)) db_start (
    .clk   (clk),
    .rst_n (rst_n),
    .sw_in (start_btn),
    .sw_out(clean_start_btn)
  );

  // select_btn — single instance
  debounce #(.THRESHOLD(50000)) db_select (
    .clk   (clk),
    .rst_n (rst_n),
    .sw_in (select_btn),
    .sw_out(clean_select_btn)
  );

  // ── Internal registers ─────────────────────────────────────────
  logic [3:0]  reg_face_btn;
  logic [3:0]  reg_dpad;
  logic [1:0]  reg_bumper;
  logic        reg_start_btn;
  logic        reg_select_btn;
  logic        poll_tick;
  logic [19:0] poll_cnt;
  logic        rx_valid_1;
  logic [7:0]  rx_data_1;
  logic        rx_valid_2;
  logic [7:0]  rx_data_2;
  logic [7:0]  tp_data_1;
  logic [7:0]  tp_data_2;
  logic [7:0]  pkt [0:4];
  logic        pkt_valid;
  logic [7:0]  tx_byte;
  logic        tx_start;
  logic        tx_busy;
  i2c_master   tp_left(
  .dev_addr(7'h2A),
  .clk     (clk),
  .rst_n   (rst_n),
  .start   (poll_tick),
  .reg_addr(8'h12),
  .rx_data (rx_data_1),
  .rx_valid(rx_valid_1),
  .i2c_scl (i2c_scl_1),
  .i2c_sda (i2c_sda_1)
  );
  i2c_master   tp_right(
    .dev_addr(7'h2C),
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (poll_tick),
    .reg_addr(8'h12),
    .rx_data (rx_data_2),
    .rx_valid(rx_valid_2),
    .i2c_scl (i2c_scl_2),
    .i2c_sda (i2c_sda_2)
  );
  input_mapper mapper (
    .clk        (clk),
    .rst_n      (rst_n),
    .face_btn   (reg_face_btn),
    .dpad       (reg_dpad),
    .bumpers    (reg_bumper),
    .start_btn  (reg_start_btn),
    .select_btn (reg_select_btn),
    .tp_data_1  (tp_data_1),
    .tp_data_2  (tp_data_2),
    .poll_tick  (poll_tick),
    .pkt        (pkt),
    .pkt_valid  (pkt_valid)
  );
  tx_encoder enc (
    .clk        (clk),
    .rst_n      (rst_n),
    .pkt        (pkt),
    .pkt_valid  (pkt_valid),
    .tx_byte    (tx_byte),
    .tx_start   (tx_start),
    .tx_busy    (tx_busy)
  );
  uart_tx uart (
    .clk        (clk),
    .rst_n      (rst_n),
    .tx_byte    (tx_byte),
    .tx_start   (tx_start),
    .tx_pin     (tx_pin),
    .tx_busy    (tx_busy)
  );
  // ── Parallel logic: Debounce section ───────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_face_btn      <= 4'b0;
      reg_dpad          <= 4'b0;
      reg_bumper        <= 2'b0;
      reg_start_btn     <= 1'b0;
      reg_select_btn    <= 1'b0;
    end else begin
      // Latch debounced digital inputs
      reg_face_btn   <= clean_face_btn;
      reg_dpad       <= clean_dpad;
      reg_bumper     <= clean_bumper;
      reg_start_btn  <= clean_start_btn;
      reg_select_btn <= clean_select_btn;
    end
  end
  // ── Parallel logic: I2C polling section ───────────────────────────────────────────
  localparam POLL_DIV = 500_000;

  assign poll_tick = (poll_cnt == POLL_DIV -1);

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)         poll_cnt <= '0;
    else if(poll_tick) poll_cnt <= '0;
    else               poll_cnt <= poll_cnt +1'b1;
  end
  // ── Parallel logic: rx_valid_holding sec.───────────────────────────────────────────
  
  always_ff @(posedge clk or negedge rst_n) begin
      if(!rst_n)     begin
       tp_data_1 <= 1'b0;
       tp_data_2 <= 1'b0;
      end else begin
        if(rx_valid_1) tp_data_1 <= rx_data_1;
        if(rx_valid_2) tp_data_2 <= rx_data_2;
    end 
  end
endmodule
