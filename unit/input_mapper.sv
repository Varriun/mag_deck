module input_mapper (
  input  logic        clk,
  input  logic        rst_n,

  // Debounced/latched inputs from mag_deck_core — all stable, safe to sample any time
  input  logic [3:0]  face_btn,
  input  logic [3:0]  dpad,
  input  logic [1:0]  bumpers,
  input  logic        start_btn,
  input  logic        select_btn,
  input  logic [7:0]  tp_data_1,
  input  logic [7:0]  tp_data_2,

  // 100 Hz strobe from the poll timer — your trigger to emit a new packet
  input  logic        poll_tick,

  // 5-byte output packet; pkt[0] is the first byte sent (the sync byte)
  output logic [7:0]  pkt [0:4],

  // Pulses high for one clock cycle to tell tx_encoder a fresh packet is ready
  output logic        pkt_valid
);

  localparam SYNC = 8'hAA;

  // ── Packet assembly ───────────────────────────────────────────────────────
  //
  // Agreed layout:
  //   pkt[0]  =  0xAA => 1010 1010                                  (sync)
  //   pkt[1]  =  [  _  |  _  |  _  |  _  | start | select | bumpers[1:0] ]
  //   pkt[2]  =  [ face_btn[3:0]  |  dpad[3:0] ]
  //   pkt[3]  =  tp_data_1[7:0]
  //   pkt[4]  =  tp_data_2[7:0]
  //
  // This block is purely combinational — think of it as a bundle of wires
  // routing input bits into output byte slots. No clock needed.
  // Use curly-brace concatenation {} to pack bits together.
  //
  //   Example:  {4'b0000, a, b, c[1:0]}  →  8-bit value, MSB first
  //
  // Tie spare bits to 1'b0 for now (headroom for L3/R3 later).
  // The simulator will warn if your concatenation doesn't total exactly 8 bits —
  // treat that warning as a bit-count check on yourself.

  always_comb begin
    pkt[0] = SYNC;
    pkt[1] = {4'b0000, start_btn, select_btn, bumpers[1:0]};
    pkt[2] = {face_btn[3:0],dpad[3:0]};
    pkt[3] = tp_data_1[7:0];
    pkt[4] = tp_data_2[7:0];
  end

  // ── pkt_valid strobe ─────────────────────────────────────────────────────
  //
  // tx_encoder watches pkt_valid to know when to start sending.
  // It expects a one-cycle pulse each time a fresh packet is ready.
  //
  // Look at how poll_tick is generated in mag_deck_core — it is already
  // a one-cycle pulse at 100 Hz. Ask yourself: does pkt_valid need its own
  // flip-flop and counter, or is it just another name for something that
  // already exists?

  assign pkt_valid = poll_tick;


endmodule
